import Foundation

struct SnapshotResult: Sendable {
    var fileCount: Int
    var totalBytes: Int64
    var deniedCount: Int
    var incomplete: Bool
}

struct SnapshotScanProgress: Sendable, Equatable {
    enum Phase: Sendable {
        case preparing
        case counting
        case scanning
        case finishing
    }

    var phase: Phase
    var processedItems: Int
    var totalItems: Int?
    var fileCount: Int
    var totalBytes: Int64
    var currentPath: String

    var fraction: Double? {
        guard let totalItems, totalItems > 0 else { return phase == .finishing ? 1 : nil }
        return min(max(Double(processedItems) / Double(totalItems), 0), 1)
    }
}

struct SnapshotEngine: Sendable {
    private let skipNames: Set<String> = [".Spotlight-V100", ".fseventsd"]

    func scan(
        root: URL,
        into store: SnapshotStore,
        progress: (SnapshotScanProgress) -> Void = { _ in },
        shouldCancel: () -> Bool
    ) throws -> SnapshotResult {
        var fileCount = 0
        var totalBytes: Int64 = 0
        var deniedCount = 0
        var nextId: Int64 = 1
        var idByPath: [String: Int64] = [:]

        let rootResolved = PathNormalizer.resolve(root)
        progress(SnapshotScanProgress(
            phase: .preparing,
            processedItems: 0,
            totalItems: nil,
            fileCount: 0,
            totalBytes: 0,
            currentPath: rootResolved.path
        ))
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
        let totalItems = countItems(
            root: rootResolved,
            keys: keys,
            progress: progress,
            shouldCancel: shouldCancel
        )
        if shouldCancel() {
            return SnapshotResult(fileCount: 0, totalBytes: 0, deniedCount: 0, incomplete: true)
        }
        progress(SnapshotScanProgress(
            phase: .scanning,
            processedItems: 0,
            totalItems: totalItems,
            fileCount: 0,
            totalBytes: 0,
            currentPath: rootResolved.path
        ))

        guard let enumerator = FileManager.default.enumerator(
            at: rootResolved,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return SnapshotResult(fileCount: 0, totalBytes: 0, deniedCount: 0, incomplete: true)
        }

        var processedItems = 0
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
            processedItems += 1

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

            if processedItems.isMultiple(of: 128) {
                progress(SnapshotScanProgress(
                    phase: .scanning,
                    processedItems: processedItems,
                    totalItems: totalItems,
                    fileCount: fileCount,
                    totalBytes: totalBytes,
                    currentPath: relative
                ))
            }
        }

        progress(SnapshotScanProgress(
            phase: .finishing,
            processedItems: totalItems,
            totalItems: totalItems,
            fileCount: fileCount,
            totalBytes: totalBytes,
            currentPath: rootResolved.path
        ))
        return SnapshotResult(fileCount: fileCount, totalBytes: totalBytes, deniedCount: deniedCount, incomplete: false)
    }

    private func countItems(
        root: URL,
        keys: [URLResourceKey],
        progress: (SnapshotScanProgress) -> Void,
        shouldCancel: () -> Bool
    ) -> Int {
        progress(SnapshotScanProgress(
            phase: .counting,
            processedItems: 0,
            totalItems: nil,
            fileCount: 0,
            totalBytes: 0,
            currentPath: root.path
        ))
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return 0 }

        var count = 0
        while let item = enumerator.nextObject() as? URL {
            if shouldCancel() { break }
            let name = item.lastPathComponent
            if skipNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            if root.path == "/" && item.path.hasPrefix("/System") {
                enumerator.skipDescendants()
                continue
            }
            count += 1
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true || values?.isReadable == false {
                enumerator.skipDescendants()
            }
            if count.isMultiple(of: 256) {
                progress(SnapshotScanProgress(
                    phase: .counting,
                    processedItems: count,
                    totalItems: nil,
                    fileCount: 0,
                    totalBytes: 0,
                    currentPath: relativePath(of: item, root: root)
                ))
            }
        }
        return count
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
