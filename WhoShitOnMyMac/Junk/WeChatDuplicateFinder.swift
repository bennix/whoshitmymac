import CryptoKit
import Foundation

enum WeChatDuplicateFinder {
    /// 仅匹配「文件名末尾、扩展名之前」的 (1) / （2），标题中间的中文括号不算副本。
    private static let copyRegex = try! NSRegularExpression(
        pattern: #"^.+[\(（]\d+[\)）](?:\.[^.]+)?$"#
    )

    static func isCopyFilename(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        guard let match = copyRegex.firstMatch(in: name, options: [], range: range) else {
            return false
        }
        return match.range.length == name.utf16.count
    }

    static func defaultWeChatFilesRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(
            "Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files"
        )
    }

    struct Copy: Equatable, Sendable {
        var url: URL
        var originalURL: URL
        var bytes: Int64
    }

    /// 副本：带数字括号后缀，且存在一份不含该后缀的文件与其 MD5 相同。
    static func findTrashableCopies(in root: URL) -> [Copy] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }

        var copies: [URL] = []
        var keepers: [URL] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values?.isDirectory == true { continue }
            let isFile = values?.isRegularFile ?? FileManager.default.isReadableFile(atPath: url.path)
            guard isFile else { continue }
            if isCopyFilename(url.lastPathComponent) {
                copies.append(url)
            } else {
                keepers.append(url)
            }
        }

        guard !copies.isEmpty, !keepers.isEmpty else { return [] }

        var originalByHash: [String: URL] = [:]
        var keeperBySize: [Int64: [URL]] = [:]
        for url in keepers {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            keeperBySize[size, default: []].append(url)
        }

        var trashable: [Copy] = []
        for copy in copies {
            guard let digest = md5(copy) else { continue }
            let size = (try? copy.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            if originalByHash[digest] == nil {
                for keeper in keeperBySize[size] ?? [] {
                    guard let keeperDigest = md5(keeper) else { continue }
                    if originalByHash[keeperDigest] == nil {
                        originalByHash[keeperDigest] = keeper
                    }
                    if keeperDigest == digest { break }
                }
            }
            if let original = originalByHash[digest] {
                trashable.append(Copy(url: copy, originalURL: original, bytes: size))
            }
        }
        return trashable
    }

    private static func md5(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
