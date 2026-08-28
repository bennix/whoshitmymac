import Foundation

struct SnapshotResult: Sendable {
    var fileCount: Int
    var totalBytes: Int64
    var deniedCount: Int
    var incomplete: Bool
}

struct SnapshotEngine: Sendable {
    private let skipNames: Set<String> = [".Spotlight-V100", ".fseventsd"]

    func scan(root: URL, into store: SnapshotStore, shouldCancel: () -> Bool) throws -> SnapshotResult {
        var fileCount = 0
        var totalBytes: Int64 = 0
        var deniedCount = 0
        var nextId: Int64 = 1
        var idByPath: [String: Int64] = [:]

        let rootResolved = PathNormalizer.resolve(root)
        let rootNode = SnapshotNode(
            parentId: nil,
            name: "",
            isDirectory: true,
            size: 0,
            allocSize: 0,
            mtime: 0,
            inode: 0,
            flags: []
        )
        try store.insert(rootNode, id: nextId)
        idByPath[""] = nextId
        nextId += 1

        if shouldCancel() {
            return SnapshotResult(fileCount: 0, totalBytes: 0, deniedCount: 0, incomplete: true)
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .fileAllocatedSizeKey,
            .contentModificationDateKey, .fileResourceIdentifierKey, .isReadableKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: rootResolved,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return SnapshotResult(fileCount: 0, totalBytes: 0, deniedCount: 0, incomplete: true)
        }

        while let item = enumerator.nextObject() as? URL {
            if shouldCancel() {
                return SnapshotResult(fileCount: fileCount, totalBytes: totalBytes, deniedCount: deniedCount, incomplete: true)
            }
            let values = try? item.resourceValues(forKeys: Set(keys))
            let name = item.lastPathComponent
            if skipNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            if rootResolved.path == "/" && item.path.hasPrefix("/System") {
                enumerator.skipDescendants()
                continue
            }

            let relative = relativePath(of: item, root: rootResolved)
            let parentRelative = relative.split(separator: "/").dropLast().joined(separator: "/")
            let parentId = idByPath[parentRelative] ?? idByPath[""]

            var flags: SnapshotNodeFlags = []
            let isLink = values?.isSymbolicLink == true
            if isLink { flags.insert(.symlink) }
            let readable = values?.isReadable ?? true
            if !readable {
                flags.insert(.denied)
                deniedCount += 1
            }
            let isDir = values?.isDirectory == true && !isLink
            let size = Int64(values?.fileSize ?? 0)
            let allocated = values?.fileAllocatedSize.map(Int64.init) ?? size
            if !isDir {
                fileCount += 1
                totalBytes += allocated
            }

            let node = SnapshotNode(
                parentId: parentId,
                name: name,
                isDirectory: isDir || isLink,
                size: size,
                allocSize: allocated,
                mtime: Int64(values?.contentModificationDate?.timeIntervalSince1970 ?? 0),
                inode: 0,
                flags: flags
            )
            try store.insert(node, id: nextId)
            idByPath[relative] = nextId
            nextId += 1

            if isLink || !readable {
                enumerator.skipDescendants()
            }
        }

        return SnapshotResult(fileCount: fileCount, totalBytes: totalBytes, deniedCount: deniedCount, incomplete: false)
    }

    private func relativePath(of url: URL, root: URL) -> String {
        let full = url.standardizedFileURL.path
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if full.hasPrefix(prefix) {
            return String(full.dropFirst(prefix.count))
        }
        if full == root.path { return "" }
        return url.lastPathComponent
    }
}
