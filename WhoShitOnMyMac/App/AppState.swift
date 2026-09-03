import AppKit
import Foundation
import Observation

enum SidebarItem: String, CaseIterable, Identifiable {
    case snapshots = "扫描"
    case junk = "垃圾"
    case wechat = "微信"
    case apps = "应用"
    case settings = "设置"
    var id: String { rawValue }
}

struct InstalledApp: Identifiable, Hashable, Sendable {
    var url: URL
    var name: String
    var bundleId: String
    var bytes: Int64?
    var isRunning: Bool

    var id: String { url.path }
}

@Observable
final class AppState {
    var permission = PermissionGate.default
    var permissionStatus: PermissionStatus
    var sidebar: SidebarItem = .snapshots
    var queue = TrashQueue()
    var whitelist: WhitelistStore
    var lastMessage: String?
    var isScanning = false
    var scanProgress = "准备扫描"
    var scanFraction: Double?
    var scanDetail = ""
    var isScanningJunk = false
    var isScanningWeChat = false
    var isLoadingApps = false
    var appLoadProgress = ""
    var junkItems: [JunkItem] = []
    var selectedJunk: Set<String> = []
    var installedApps: [InstalledApp] = []
    var selectedApp: InstalledApp?
    var uninstallPlan: UninstallPlan?
    var selectedResidues: Set<String> = []
    var diffEntries: [DiffEntry] = []
    var selectedDiffs: Set<String> = []
    var isLoadingSnapshotEntries = false
    var currentSnapshotID: UUID?
    var showDryRun = false
    var showOnboarding: Bool
    var lastExecuteFailed: [(URL, String)] = []
    var isTrashing = false
    var isQuittingApp = false
    var allowPermanentDelete = false
    var whitelistDraft = ""

    init() {
        permissionStatus = PermissionGate.default.status()
        whitelist = WhitelistStore(fileURL: AppPaths.whitelistFile)
        showOnboarding = !UserDefaults.standard.bool(forKey: "hasSeenPermissionOnboarding")
    }

    func refreshPermissions() {
        permissionStatus = permission.status()
    }

    func enqueue(url: URL, bytes: Int64, source: String) {
        let rejection = queue.enqueue(
            TrashTask(url: url, bytes: bytes, source: source),
            appSupport: AppPaths.applicationSupport,
            whitelist: { self.whitelist.contains($0) }
        )
        switch rejection {
        case .blacklisted:
            lastMessage = "已拦截黑名单路径"
        case .whitelisted:
            lastMessage = "白名单保护，未入队"
        case nil:
            lastMessage = nil
        }
    }

    func setJunkSelected(_ item: JunkItem, selected: Bool, source: String = "垃圾") {
        if selected {
            let rejection = queue.enqueue(
                TrashTask(url: item.path, bytes: item.bytes, source: source),
                appSupport: AppPaths.applicationSupport,
                whitelist: { self.whitelist.contains($0) }
            )
            if rejection == nil {
                selectedJunk.insert(item.id)
            } else {
                lastMessage = rejection == .blacklisted ? "已拦截黑名单路径" : "白名单保护，未入队"
            }
        } else {
            selectedJunk.remove(item.id)
            let path = PathNormalizer.resolve(item.path).path
            queue.tasks.removeAll {
                $0.source == "垃圾" && PathNormalizer.resolve($0.url).path == path
            }
        }
    }

    func selectAllJunk() {
        for item in junkItems where item.skipReason == .none {
            setJunkSelected(item, selected: true)
        }
    }

    func clearJunkSelection() {
        selectedJunk.removeAll()
        queue.tasks.removeAll { $0.source == "垃圾" }
    }

    func setDiffSelected(_ entry: DiffEntry, rootPath: String, selected: Bool) {
        let url = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(entry.relativePath)
        let resolvedPath = PathNormalizer.resolve(url).path
        if selected {
            let rejection = queue.enqueue(
                TrashTask(url: url, bytes: entry.currentSize ?? 0, source: "快照"),
                appSupport: AppPaths.applicationSupport,
                whitelist: { self.whitelist.contains($0) }
            )
            if rejection == nil {
                selectedDiffs.insert(entry.id)
            } else {
                lastMessage = rejection == .blacklisted ? "已拦截黑名单路径" : "白名单保护，未入队"
            }
        } else {
            selectedDiffs.remove(entry.id)
            queue.tasks.removeAll {
                $0.source == "快照" && PathNormalizer.resolve($0.url).path == resolvedPath
            }
        }
    }

    func selectAllDiffs(rootPath: String) {
        for entry in diffEntries where entry.currentSize != nil && entry.kind != .incomparable && entry.kind != .unchanged {
            setDiffSelected(entry, rootPath: rootPath, selected: true)
        }
    }

    func clearDiffSelection() {
        selectedDiffs.removeAll()
        queue.tasks.removeAll { $0.source == "快照" }
    }

    func runTrash() {
        guard !isTrashing, !queue.tasks.isEmpty else { return }
        isTrashing = true
        lastExecuteFailed = []
        let pendingQueue = queue
        let before = volumeFree()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = TrashRunner().execute(pendingQueue)
            var succeeded = outcome.succeeded
            var failed = outcome.failed
            let administratorTasks = AdministratorTrashRunner.retryTasks(
                in: pendingQueue,
                failedURLs: failed.map(\.0)
            )
            if !administratorTasks.isEmpty {
                for task in administratorTasks where task.source == "卸载" {
                    guard let bundleIdentifier = Bundle(url: task.url)?.bundleIdentifier else { continue }
                    _ = AppProcessController.quit(appURL: task.url, bundleIdentifier: bundleIdentifier)
                }
                let administratorOutcome = AdministratorTrashRunner().execute(administratorTasks)
                let attemptedPaths = Set(administratorTasks.map { PathNormalizer.resolve($0.url).path })
                succeeded.append(contentsOf: administratorOutcome.succeeded)
                failed = failed.filter { !attemptedPaths.contains(PathNormalizer.resolve($0.0).path) }
                    + administratorOutcome.failed
                try? OperationLog(fileURL: AppPaths.operationsLog).append(
                    "automatic admin trash ok=\(administratorOutcome.ok) failed=\(administratorOutcome.failed.count)"
                )
            }
            let after = self?.volumeFree() ?? before
            let delta = after - before
            try? OperationLog(fileURL: AppPaths.operationsLog).append(
                "trash ok=\(succeeded.count) failed=\(failed.count) delta=\(delta)"
            )
            for failure in failed {
                try? OperationLog(fileURL: AppPaths.operationsLog).append(
                    "trash failed path=\(failure.0.path) error=\(failure.1)"
                )
            }
            let completedURLs = succeeded
            let finalFailures = failed
            let succeededPaths = Set(completedURLs.map { PathNormalizer.resolve($0).path })
            let succeededSnapshotNames = Set<String>(pendingQueue.tasks.compactMap { task -> String? in
                guard task.source == "快照", succeededPaths.contains(PathNormalizer.resolve(task.url).path) else { return nil }
                return task.url.lastPathComponent
            })
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastExecuteFailed = finalFailures
                self.queue.tasks.removeAll { succeededPaths.contains(PathNormalizer.resolve($0.url).path) }
                self.junkItems.removeAll { succeededPaths.contains(PathNormalizer.resolve($0.path).path) }
                self.selectedJunk.subtract(succeededPaths)
                self.diffEntries.removeAll { succeededSnapshotNames.contains($0.relativePath) }
                self.selectedDiffs.subtract(succeededSnapshotNames)
                self.reconcileInstalledApps(afterRemoving: completedURLs)
                self.isTrashing = false
                if let firstFailure = finalFailures.first {
                    self.lastMessage = "完成 \(completedURLs.count) 项，失败 \(finalFailures.count)：\(firstFailure.1)"
                    self.showDryRun = true
                } else {
                    self.lastMessage = "完成 \(completedURLs.count) 项，可用空间变化 \(ByteFormat.string(delta))"
                }
            }
        }
    }

    func runTrashWithAdministratorPrivileges() {
        guard !isTrashing else { return }
        let failedPaths = Set(lastExecuteFailed.map { PathNormalizer.resolve($0.0).path })
        let tasks = queue.tasks.filter {
            failedPaths.contains(PathNormalizer.resolve($0.url).path)
                && AdministratorTrashRunner.canHandle($0)
        }
        guard !tasks.isEmpty else { return }
        isTrashing = true
        let attemptedPaths = Set(tasks.map { PathNormalizer.resolve($0.url).path })
        let unhandledFailures = lastExecuteFailed.filter {
            !attemptedPaths.contains(PathNormalizer.resolve($0.0).path)
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for task in tasks where task.source == "卸载" {
                guard let bundleIdentifier = Bundle(url: task.url)?.bundleIdentifier else { continue }
                _ = AppProcessController.quit(appURL: task.url, bundleIdentifier: bundleIdentifier)
            }
            let outcome = AdministratorTrashRunner().execute(tasks)
            for failure in outcome.failed {
                try? OperationLog(fileURL: AppPaths.operationsLog).append(
                    "admin trash failed path=\(failure.0.path) error=\(failure.1)"
                )
            }
            try? OperationLog(fileURL: AppPaths.operationsLog).append(
                "admin trash ok=\(outcome.ok) failed=\(outcome.failed.count)"
            )
            let succeededPaths = Set(outcome.succeeded.map { PathNormalizer.resolve($0).path })
            DispatchQueue.main.async {
                guard let self else { return }
                self.queue.tasks.removeAll { succeededPaths.contains(PathNormalizer.resolve($0.url).path) }
                self.reconcileInstalledApps(afterRemoving: outcome.succeeded)
                self.lastExecuteFailed = unhandledFailures + outcome.failed
                self.isTrashing = false
                if self.lastExecuteFailed.isEmpty {
                    self.lastMessage = "已使用管理员权限将 \(outcome.ok) 个项目移到废纸篓"
                    self.showDryRun = false
                } else {
                    self.lastMessage = "管理员重试完成 \(outcome.ok) 项，仍失败 \(self.lastExecuteFailed.count) 项"
                }
            }
        }
    }

    var canRetryFailedItemsWithAdministratorPrivileges: Bool {
        let failedPaths = Set(lastExecuteFailed.map { PathNormalizer.resolve($0.0).path })
        return queue.tasks.contains {
            failedPaths.contains(PathNormalizer.resolve($0.url).path)
                && AdministratorTrashRunner.canHandle($0)
        }
    }

    var mayRequestAdministratorPrivileges: Bool {
        queue.tasks.contains { AdministratorTrashRunner.canHandle($0) }
    }

    func pruneMissingInstalledApps() {
        reconcileInstalledApps(afterRemoving: [])
    }

    private func reconcileInstalledApps(afterRemoving removedURLs: [URL]) {
        installedApps = Self.remainingInstalledApps(
            installedApps,
            afterRemoving: removedURLs,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
        if let selectedApp,
           !installedApps.contains(where: { $0.id == selectedApp.id }) {
            self.selectedApp = nil
            uninstallPlan = nil
            selectedResidues.removeAll()
        }
    }

    static func remainingInstalledApps(
        _ apps: [InstalledApp],
        afterRemoving removedURLs: [URL],
        fileExists: (String) -> Bool
    ) -> [InstalledApp] {
        let removedPaths = Set(removedURLs.map { PathNormalizer.resolve($0).path })
        return apps.filter { app in
            let path = PathNormalizer.resolve(app.url).path
            return !removedPaths.contains(path) && fileExists(app.url.path)
        }
    }

    func loadInstalledApps() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        appLoadProgress = "正在读取 Applications…"
        lastMessage = nil
        let roots = Self.installedAppRoots
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var result = Self.discoverInstalledApps(in: roots, runningBundleIDs: runningBundleIDs)
            DispatchQueue.main.async {
                guard let self else { return }
                self.installedApps = result
                self.appLoadProgress = result.isEmpty ? "没有找到可管理的应用" : "已找到 \(result.count) 个应用，正在统计体积…"
                if result.isEmpty { self.isLoadingApps = false }
            }
            for index in result.indices {
                result[index].bytes = Self.directorySize(result[index].url)
                let updated = result[index]
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let stateIndex = self.installedApps.firstIndex(where: { $0.id == updated.id }) {
                        self.installedApps[stateIndex].bytes = updated.bytes
                    }
                    self.appLoadProgress = "正在统计应用体积 \(index + 1)/\(result.count)"
                    if index == result.indices.last {
                        self.installedApps.sort { ($0.bytes ?? -1) > ($1.bytes ?? -1) }
                        self.isLoadingApps = false
                        self.appLoadProgress = ""
                        self.lastMessage = "已载入 \(result.count) 个应用"
                    }
                }
            }
        }
    }

    private static var installedAppRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
    }

    static func discoverInstalledApps(in roots: [URL], runningBundleIDs: Set<String>) -> [InstalledApp] {
        var result: [InstalledApp] = []
        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for appURL in children where appURL.pathExtension == "app" {
                guard let bundle = Bundle(url: appURL), let bundleId = bundle.bundleIdentifier else { continue }
                if Blacklist.blocksBundleId(bundleId) { continue }
                if appURL.path.hasPrefix("/System") { continue }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? appURL.deletingPathExtension().lastPathComponent
                result.append(InstalledApp(
                    url: appURL,
                    name: name,
                    bundleId: bundleId,
                    bytes: nil,
                    isRunning: runningBundleIDs.contains(bundleId)
                ))
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func makeUninstallPlan(for app: InstalledApp) {
        selectedApp = app
        let others = Set(installedApps.filter { $0.bundleId == app.bundleId && $0.url.path != app.url.path }.map(\.bundleId))
        let plan = UninstallEngine.plan(
            appURL: app.url,
            bundleId: app.bundleId,
            displayName: app.name,
            home: FileManager.default.homeDirectoryForCurrentUser,
            otherInstalledIds: others
        )
        uninstallPlan = plan
        selectedResidues = Set(plan.residues.filter(\.selectedByDefault).map(\.id))
    }

    func enqueueSelectedUninstall(forceQuitIfRunning: Bool) {
        guard let app = selectedApp,
              let plan = uninstallPlan,
              !plan.blocked,
              PathNormalizer.resolve(app.url).path == PathNormalizer.resolve(plan.appURL).path else { return }
        let selectedResidueIDs = selectedResidues
        let isRunning = AppProcessController.isRunning(appURL: app.url, bundleIdentifier: app.bundleId)
        updateRunningState(for: app, isRunning: isRunning)
        if isRunning && !forceQuitIfRunning {
            lastMessage = "应用仍在运行，请先退出或选择强制退出后继续"
            return
        }
        guard isRunning else {
            enqueueUninstallItems(app: app, plan: plan, selectedResidueIDs: selectedResidueIDs)
            return
        }

        isQuittingApp = true
        lastMessage = "正在退出 \(app.name)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = AppProcessController.quit(appURL: app.url, bundleIdentifier: app.bundleId)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isQuittingApp = false
                let stillRunning = AppProcessController.isRunning(appURL: app.url, bundleIdentifier: app.bundleId)
                self.updateRunningState(for: app, isRunning: stillRunning)
                guard !stillRunning, outcome != .failed else {
                    self.lastMessage = "无法退出 \(app.name)，请保存工作后重试或在活动监视器中检查其进程"
                    return
                }
                self.enqueueUninstallItems(app: app, plan: plan, selectedResidueIDs: selectedResidueIDs)
                self.lastMessage = outcome == .forceTerminated
                    ? "已强制退出 \(app.name) 并加入待删除"
                    : "已退出 \(app.name) 并加入待删除"
            }
        }
    }

    func refreshInstalledAppRunningStates() {
        for index in installedApps.indices {
            installedApps[index].isRunning = AppProcessController.isRunning(
                appURL: installedApps[index].url,
                bundleIdentifier: installedApps[index].bundleId
            )
        }
        if let selectedApp,
           let updated = installedApps.first(where: { $0.id == selectedApp.id }) {
            self.selectedApp = updated
        }
    }

    private func enqueueUninstallItems(
        app: InstalledApp,
        plan: UninstallPlan,
        selectedResidueIDs: Set<String>
    ) {
        enqueue(url: plan.appURL, bytes: app.bytes ?? 0, source: "卸载")
        for item in plan.residues where selectedResidueIDs.contains(item.id) {
            enqueue(url: item.url, bytes: 0, source: "卸载残留")
        }
        if lastMessage == nil {
            lastMessage = "已将 \(app.name) 及选中的残留加入待删除"
        }
    }

    private func updateRunningState(for app: InstalledApp, isRunning: Bool) {
        if let index = installedApps.firstIndex(where: { $0.id == app.id }) {
            installedApps[index].isRunning = isRunning
        }
        if selectedApp?.id == app.id {
            selectedApp?.isRunning = isRunning
        }
    }

    func scanJunk() {
        guard !isScanningJunk else { return }
        isScanningJunk = true
        lastMessage = nil
        let knownApps = installedApps
        let whitelist = whitelist
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let apps = knownApps.isEmpty
                ? Self.discoverInstalledApps(in: Self.installedAppRoots, runningBundleIDs: runningBundleIDs)
                : knownApps
            let installedBundleIDs = Set(apps.map(\.bundleId))
            let browserIDs = Set(["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox"])
            let engine = JunkEngine(
                rules: JunkRule.bundledDefaults,
                home: FileManager.default.homeDirectoryForCurrentUser,
                now: Date(),
                isBusy: { group in
                    group == .browsers && !runningBundleIDs.isDisjoint(with: browserIDs)
                },
                isInstalledBundle: { installedBundleIDs.contains($0) }
            )
            let items = engine.scan(
                blacklist: { Blacklist.blocks($0, appSupport: AppPaths.applicationSupport) },
                whitelist: { whitelist.contains($0) }
            )
            DispatchQueue.main.async {
                guard let self else { return }
                if self.installedApps.isEmpty { self.installedApps = apps }
                self.junkItems = items
                self.selectedJunk = []
                self.isScanningJunk = false
                self.lastMessage = "垃圾扫描完成，共发现 \(items.count) 项"
            }
        }
    }

    func scanWeChatDuplicates() {
        guard !isScanningWeChat else { return }
        isScanningWeChat = true
        lastMessage = nil
        let whitelist = whitelist
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let engine = JunkEngine(
                rules: [],
                home: FileManager.default.homeDirectoryForCurrentUser,
                now: Date(),
                isBusy: { _ in false },
                isInstalledBundle: { _ in false }
            )
            let found = engine.wechatDuplicateItems(
                blacklist: { Blacklist.blocks($0, appSupport: AppPaths.applicationSupport) },
                whitelist: { whitelist.contains($0) }
            )
            DispatchQueue.main.async {
                guard let self else { return }
                self.junkItems.removeAll { $0.group == .wechatDupes }
                self.junkItems.append(contentsOf: found)
                for item in found {
                    self.selectedJunk.remove(item.id)
                }
                self.isScanningWeChat = false
                self.lastMessage = found.isEmpty
                    ? "没有找到与原件 MD5 相同的微信括号副本"
                    : "微信副本 \(found.count) 项，约 \(ByteFormat.string(found.reduce(0) { $0 + $1.bytes }))"
            }
        }
    }

    func selectAllWeChatDupes() {
        for item in junkItems where item.group == .wechatDupes && item.skipReason == .none {
            setJunkSelected(item, selected: true, source: "微信")
        }
    }

    func volumeFree() -> Int64 {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let cap = values?.volumeAvailableCapacityForImportantUsage {
            return Int64(cap)
        }
        return 0
    }

    private static func directorySize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            while let file = enumerator.nextObject() as? URL {
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true {
                    total += Int64(values?.fileSize ?? 0)
                }
            }
        }
        return total
    }
}
