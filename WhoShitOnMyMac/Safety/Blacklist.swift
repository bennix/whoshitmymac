import Foundation

enum Blacklist {
    static func blocksBundleId(_ id: String) -> Bool {
        let lower = id.lowercased()
        if lower.hasPrefix("com.apple.") { return true }
        if lower == "fudan.whoshitonmymac" || lower == "com.bennix.whoshitmymac" { return true }
        return false
    }

    static func blocks(_ url: URL, appSupport: URL, bundleId: String = "fudan.WhoShitOnMyMac") -> Bool {
        _ = bundleId
        let path = PathNormalizer.resolve(url).path
        if isPrefix(path, of: "/System") { return true }
        if isPrefix(path, of: "/usr") { return true }
        if isPrefix(path, of: "/bin") { return true }
        if isPrefix(path, of: "/sbin") { return true }
        let support = PathNormalizer.resolve(appSupport).path
        if isPrefix(path, of: support) { return true }
        return false
    }

    private static func isPrefix(_ path: String, of root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
