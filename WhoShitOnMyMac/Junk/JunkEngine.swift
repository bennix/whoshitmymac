import Foundation

enum JunkGroup: String, Codable, Sendable, CaseIterable {
    case caches, logs, trash, browsers, devCaches, orphans, installers, artifacts, sensitive, wechatDupes
}

enum SkipReason: String, Equatable, Sendable {
    case none
    case busy
    case whitelist
    case blacklist
    case unproven
    case recentActivity
}

struct JunkItem: Equatable, Sendable, Identifiable {
    var path: URL
    var bytes: Int64
    var group: JunkGroup
    var skipReason: SkipReason
    var selectedByDefault: Bool
    var detail: String

    var id: String { path.path }

    init(
        path: URL,
        bytes: Int64,
        group: JunkGroup,
        skipReason: SkipReason,
        selectedByDefault: Bool,
        detail: String = ""
    ) {
        self.path = path
        self.bytes = bytes
        self.group = group
        self.skipReason = skipReason
        self.selectedByDefault = selectedByDefault
        self.detail = detail
    }
}

struct JunkRule: Codable, Sendable {
    var group: JunkGroup
    var relativeHomePaths: [String]
    var installerExtensions: [String]?
    var artifactNames: [String]?

    static let bundledDefaults: [JunkRule] = [
        JunkRule(group: .caches, relativeHomePaths: ["Library/Caches"], installerExtensions: nil, artifactNames: nil),
        JunkRule(group: .logs, relativeHomePaths: ["Library/Logs"], installerExtensions: nil, artifactNames: nil),
        JunkRule(group: .installers, relativeHomePaths: ["Downloads", "Desktop"], installerExtensions: ["dmg", "pkg", "mpkg", "iso", "xip"], artifactNames: nil),
        JunkRule(group: .artifacts, relativeHomePaths: ["Projects", "Developer", "GitHub", "dev"], installerExtensions: nil, artifactNames: ["node_modules", "target", ".build", "dist"]),
        JunkRule(group: .orphans, relativeHomePaths: ["Library/Application Support"], installerExtensions: nil, artifactNames: nil),
        JunkRule(group: .sensitive, relativeHomePaths: ["Library/Application Support/MobileSync/Backup"], installerExtensions: nil, artifactNames: nil)
    ]
}

struct JunkEngine: Sendable {
    var rules: [JunkRule]
    var home: URL
    var now: Date
    var isBusy: @Sendable (JunkGroup) -> Bool
    var isInstalledBundle: @Sendable (String) -> Bool

    func scan(blacklist: (URL) -> Bool, whitelist: (URL) -> Bool) -> [JunkItem] {
        var items: [JunkItem] = []
        for rule in rules {
            if isBusy(rule.group) {
                continue
            }
            switch rule.group {
            case .installers:
                items.append(contentsOf: scanInstallers(rule, blacklist: blacklist, whitelist: whitelist))
            case .artifacts:
                items.append(contentsOf: scanArtifacts(rule, blacklist: blacklist, whitelist: whitelist))
            case .orphans:
                items.append(contentsOf: scanOrphans(rule, blacklist: blacklist, whitelist: whitelist))
            case .wechatDupes:
                break
            default:
                items.append(contentsOf: scanDirectories(rule, blacklist: blacklist, whitelist: whitelist))
            }
        }
        items.append(contentsOf: wechatDuplicateItems(blacklist: blacklist, whitelist: whitelist))
        return items
    }

    func wechatDuplicateItems(blacklist: (URL) -> Bool, whitelist: (URL) -> Bool) -> [JunkItem] {
        if isBusy(.wechatDupes) { return [] }
        let root = WeChatDuplicateFinder.defaultWeChatFilesRoot(home: home)
        return WeChatDuplicateFinder.findTrashableCopies(in: root).compactMap { copy in
            makeItem(
                copy.url,
                group: .wechatDupes,
                blacklist: blacklist,
                whitelist: whitelist,
                skip: .none,
                detail: "原件：\(copy.originalURL.lastPathComponent)",
                bytes: copy.bytes
            )
        }
    }

    private func scanDirectories(_ rule: JunkRule, blacklist: (URL) -> Bool, whitelist: (URL) -> Bool) -> [JunkItem] {
        var items: [JunkItem] = []
        for relative in rule.relativeHomePaths {
            let container = home.appendingPathComponent(relative)
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: container,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: []
            ) else { continue }
            for child in children {
                if let item = makeItem(
                    child,
                    group: rule.group,
                    blacklist: blacklist,
                    whitelist: whitelist,
                    skip: .none
                ) {
                    items.append(item)
                }
            }
        }
        return items
    }

    private func scanInstallers(_ rule: JunkRule, blacklist: (URL) -> Bool, whitelist: (URL) -> Bool) -> [JunkItem] {
        let exts = Set((rule.installerExtensions ?? []).map { $0.lowercased() })
        var items: [JunkItem] = []
        for relative in rule.relativeHomePaths {
            let dir = home.appendingPathComponent(relative)
            guard let children = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
            for child in children where exts.contains(child.pathExtension.lowercased()) {
                if let item = makeItem(child, group: .installers, blacklist: blacklist, whitelist: whitelist, skip: .none) {
                    items.append(item)
                }
            }
        }
        return items
    }

    private func scanArtifacts(_ rule: JunkRule, blacklist: (URL) -> Bool, whitelist: (URL) -> Bool) -> [JunkItem] {
        let names = Set(rule.artifactNames ?? [])
        var items: [JunkItem] = []
        let week: TimeInterval = 7 * 24 * 60 * 60
        for relative in rule.relativeHomePaths {
            let root = home.appendingPathComponent(relative)
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            while let url = enumerator.nextObject() as? URL {
                guard names.contains(url.lastPathComponent) else { continue }
                enumerator.skipDescendants()
                var skip: SkipReason = .none
                if let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   now.timeIntervalSince(mtime) < week {
                    skip = .recentActivity
                }
                if let item = makeItem(url, group: .artifacts, blacklist: blacklist, whitelist: whitelist, skip: skip) {
                    items.append(item)
                }
            }
        }
        return items
    }

    private func scanOrphans(_ rule: JunkRule, blacklist: (URL) -> Bool, whitelist: (URL) -> Bool) -> [JunkItem] {
        var items: [JunkItem] = []
        let protectedPrefixes = ["com.1password", "com.agilebits", "com.docker", "com.apple"]
        for relative in rule.relativeHomePaths {
            let dir = home.appendingPathComponent(relative)
            guard let children = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                let name = child.lastPathComponent
                guard UninstallEngine.isValidBundleId(name) else { continue }
                if protectedPrefixes.contains(where: { name.lowercased().hasPrefix($0) }) { continue }
                if isInstalledBundle(name) { continue }
                if let item = makeItem(child, group: .orphans, blacklist: blacklist, whitelist: whitelist, skip: .none) {
                    items.append(item)
                }
            }
        }
        return items
    }

    private func makeItem(
        _ url: URL,
        group: JunkGroup,
        blacklist: (URL) -> Bool,
        whitelist: (URL) -> Bool,
        skip: SkipReason,
        detail: String = "",
        bytes: Int64? = nil
    ) -> JunkItem? {
        var reason = skip
        if blacklist(url) { reason = .blacklist }
        else if whitelist(url) { reason = .whitelist }
        return JunkItem(
            path: url,
            bytes: bytes ?? itemSize(url),
            group: group,
            skipReason: reason,
            selectedByDefault: false,
            detail: detail
        )
    }

    private func itemSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values?.isDirectory == true {
            return directorySize(url)
        }
        return Int64(values?.fileSize ?? 0)
    }

    private func directorySize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            while let file = enumerator.nextObject() as? URL {
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true {
                    total += Int64(values?.fileSize ?? 0)
                }
            }
        } else if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            total = Int64(size)
        }
        return total
    }
}
