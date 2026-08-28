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

struct InstalledApp: Identifiable, Hashable {
    var url: URL
    var name: String
    var bundleId: String
    var bytes: Int64
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
    var junkItems: [JunkItem] = []
    var selectedJunk: Set<String> = []
    var installedApps: [InstalledApp] = []
    var selectedApp: InstalledApp?
    var uninstallPlan: UninstallPlan?
    var selectedResidues: Set<String> = []
    var diffEntries: [DiffEntry] = []
    var selectedDiffs: Set<String> = []
    var baseSnapshotID: UUID?
    var currentSnapshotID: UUID?
    var showDryRun = false
    var showOnboarding: Bool
    var lastExecuteFailed: [(URL, String)] = []
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

    func runTrash() {
        let before = volumeFree()
        let runner = TrashRunner()
        let outcome = runner.execute(queue)
        lastExecuteFailed = outcome.failed
        let after = volumeFree()
        let delta = after - before
        try? OperationLog(fileURL: AppPaths.operationsLog).append(
            "trash ok=\(outcome.ok) failed=\(outcome.failed.count) delta=\(delta)"
        )
        lastMessage = "完成 \(outcome.ok) 项，失败 \(outcome.failed.count)，可用空间变化 \(ByteFormat.string(delta))"
        if outcome.failed.isEmpty {
            queue.tasks.removeAll()
        }
    }

    func loadInstalledApps() {
        var result: [InstalledApp] = []
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else { continue }
            for appURL in children where appURL.pathExtension == "app" {
                guard let bundle = Bundle(url: appURL), let bundleId = bundle.bundleIdentifier else { continue }
                if Blacklist.blocksBundleId(bundleId) { continue }
                if appURL.path.hasPrefix("/System") { continue }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? appURL.deletingPathExtension().lastPathComponent
                let bytes = directorySize(appURL)
                result.append(InstalledApp(url: appURL, name: name, bundleId: bundleId, bytes: bytes, isRunning: running.contains(bundleId)))
            }
        }
        installedApps = result.sorted { $0.bytes > $1.bytes }
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
        let engine = JunkEngine(
            rules: JunkRule.bundledDefaults,
            home: FileManager.default.homeDirectoryForCurrentUser,
            now: Date(),
            isBusy: { group in
                if group == .browsers {
                    let ids = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox"]
                    return NSWorkspace.shared.runningApplications.contains { ids.contains($0.bundleIdentifier ?? "") }
                }
                return false
            },
            isInstalledBundle: { id in
                self.installedApps.contains { $0.bundleId == id }
            }
        )
        if installedApps.isEmpty { loadInstalledApps() }
        junkItems = engine.scan(
            blacklist: { Blacklist.blocks($0, appSupport: AppPaths.applicationSupport) },
            whitelist: { self.whitelist.contains($0) }
        )
        selectedJunk = []
    }

    func volumeFree() -> Int64 {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let cap = values?.volumeAvailableCapacityForImportantUsage {
            return Int64(cap)
        }
        return 0
    }

    func directorySize(_ url: URL) -> Int64 {
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
