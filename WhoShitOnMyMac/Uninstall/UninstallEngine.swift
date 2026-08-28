import Foundation

enum ResidueMatch: String, Sendable {
    case strong, nameVariant, shared
}

struct ResidueItem: Equatable, Sendable, Identifiable {
    var url: URL
    var match: ResidueMatch
    var selectedByDefault: Bool
    var reason: String

    var id: String { url.path }
}

struct UninstallPlan: Sendable {
    var appURL: URL
    var bundleId: String
    var residues: [ResidueItem]
    var blocked: Bool
    var blockReason: String?
}

enum UninstallEngine {
    static func isValidBundleId(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        let allowed = CharacterSet.alphanumerics
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    static func plan(
        appURL: URL,
        bundleId: String,
        displayName: String,
        home: URL,
        otherInstalledIds: Set<String>,
        systemLibrary: URL = URL(fileURLWithPath: "/Library", isDirectory: true)
    ) -> UninstallPlan {
        if Blacklist.blocksBundleId(bundleId) || PathNormalizer.resolve(appURL).path.hasPrefix("/System") {
            return UninstallPlan(appURL: appURL, bundleId: bundleId, residues: [], blocked: true, blockReason: "系统应用不可卸载")
        }

        var residues: [ResidueItem] = []
        guard isValidBundleId(bundleId) else {
            return UninstallPlan(appURL: appURL, bundleId: bundleId, residues: residues, blocked: false, blockReason: nil)
        }

        let library = home.appendingPathComponent("Library")
        let strong: [URL] = [
            library.appendingPathComponent("Application Support/\(bundleId)"),
            library.appendingPathComponent("Caches/\(bundleId)"),
            library.appendingPathComponent("HTTPStorages/\(bundleId)"),
            library.appendingPathComponent("Containers/\(bundleId)"),
            library.appendingPathComponent("Preferences/\(bundleId).plist"),
            library.appendingPathComponent("LaunchAgents/\(bundleId).plist"),
            library.appendingPathComponent("Saved Application State/\(bundleId).savedState"),
            library.appendingPathComponent("Logs/\(bundleId)")
        ]
        for url in strong where FileManager.default.fileExists(atPath: url.path) {
            residues.append(ResidueItem(url: url, match: .strong, selectedByDefault: true, reason: "bundle id 强匹配"))
        }

        if displayName.count >= 2 {
            let variants = nameVariants(displayName)
            for name in variants {
                let candidate = library.appendingPathComponent("Application Support/\(name)")
                if FileManager.default.fileExists(atPath: candidate.path),
                   !residues.contains(where: { $0.url.path == candidate.path }) {
                    residues.append(ResidueItem(url: candidate, match: .nameVariant, selectedByDefault: false, reason: "显示名变体，默认不选"))
                }
            }
        }

        let groupRoot = library.appendingPathComponent("Group Containers")
        if let children = try? FileManager.default.contentsOfDirectory(at: groupRoot, includingPropertiesForKeys: nil) {
            for child in children where child.lastPathComponent.localizedCaseInsensitiveContains(bundleId) {
                let shared = otherInstalledIds.contains(bundleId)
                residues.append(ResidueItem(
                    url: child,
                    match: shared ? .shared : .strong,
                    selectedByDefault: !shared,
                    reason: shared ? "其他已装副本仍在使用" : "Group Container"
                ))
            }
        }

        let commonBundleSegments = Set(["com", "org", "net", "app", "mac", "desktop", "apple"])
        let identityTokens = Set(bundleId.lowercased().split(separator: ".").map(String.init).filter {
            $0.count >= 4 && !commonBundleSegments.contains($0)
        })
        let auxiliaryRoots = [
            home.appendingPathComponent(".config", isDirectory: true),
            systemLibrary.appendingPathComponent("LaunchAgents", isDirectory: true),
            systemLibrary.appendingPathComponent("LaunchDaemons", isDirectory: true),
            systemLibrary.appendingPathComponent("PrivilegedHelperTools", isDirectory: true),
            systemLibrary.appendingPathComponent("Application Support", isDirectory: true)
        ]
        for root in auxiliaryRoots {
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                let name = child.lastPathComponent.lowercased()
                let fullMatch = name.contains(bundleId.lowercased())
                let token = identityTokens.first(where: { name.contains($0) })
                guard fullMatch || token != nil,
                      !residues.contains(where: { PathNormalizer.resolve($0.url).path == PathNormalizer.resolve(child).path }) else { continue }
                residues.append(ResidueItem(
                    url: child,
                    match: fullMatch ? .strong : .nameVariant,
                    selectedByDefault: fullMatch,
                    reason: fullMatch ? "bundle id 强匹配" : "关联标识 \(token ?? "")，请确认后选择"
                ))
            }
        }

        return UninstallPlan(appURL: appURL, bundleId: bundleId, residues: residues, blocked: false, blockReason: nil)
    }

    private static func nameVariants(_ displayName: String) -> [String] {
        let nospace = displayName.replacingOccurrences(of: " ", with: "")
        let hyphen = displayName.replacingOccurrences(of: " ", with: "-")
        let underscore = displayName.replacingOccurrences(of: " ", with: "_")
        return Array(Set([displayName, nospace, hyphen, underscore]))
    }
}
