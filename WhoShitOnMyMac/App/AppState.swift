import AppKit
import Foundation
import Observation

enum SidebarItem: String, CaseIterable, Identifiable {
    case snapshots = "快照"
    case junk = "垃圾"
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
    var isShowingSnapshotComparison = false
    var baseSnapshotID: UUID?
    var currentSnapshotID: UUID?
    var showDryRun = false
    var showOnboarding: Bool
    var lastExecuteFailed: [(URL, String)] = []
    var isTrashing = false
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

    func setJunkSelected(_ item: JunkItem, selected: Bool) {
        if selected {
            let rejection = queue.enqueue(
                TrashTask(url: item.path, bytes: item.bytes, source: "垃圾"),
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
            let after = self?.volumeFree() ?? before
            let delta = after - before
            try? OperationLog(fileURL: AppPaths.operationsLog).append(
                "trash ok=\(outcome.ok) failed=\(outcome.failed.count) delta=\(delta)"
            )
            let succeededPaths = Set(outcome.succeeded.map { PathNormalizer.resolve($0).path })
            let succeededSnapshotNames = Set<String>(pendingQueue.tasks.compactMap { task -> String? in
                guard task.source == "快照", succeededPaths.contains(PathNormalizer.resolve(task.url).path) else { return nil }
                return task.url.lastPathComponent
            })
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastExecuteFailed = outcome.failed
                self.queue.tasks.removeAll { succeededPaths.contains(PathNormalizer.resolve($0.url).path) }
                self.junkItems.removeAll { succeededPaths.contains(PathNormalizer.resolve($0.path).path) }
                self.selectedJunk.subtract(succeededPaths)
                self.diffEntries.removeAll { succeededSnapshotNames.contains($0.relativePath) }
                self.selectedDiffs.subtract(succeededSnapshotNames)
                self.reconcileInstalledApps(afterRemoving: outcome.succeeded)
                self.isTrashing = false
                self.lastMessage = "完成 \(outcome.ok) 项，失败 \(outcome.failed.count)，可用空间变化 \(ByteFormat.string(delta))"
            }
        }
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
