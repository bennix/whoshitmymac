import Foundation

enum DiffKind: Equatable, Sendable {
    case added, removed, grew, shrunk, unchanged, incomparable
}

struct DiffEntry: Equatable, Sendable, Identifiable {
    var relativePath: String
    var isDirectory: Bool
    var kind: DiffKind
    var baseSize: Int64?
    var currentSize: Int64?
    var delta: Int64

    var id: String { relativePath }
}

enum DiffEngine {
    private struct RootSummary {
        var isDirectory: Bool
        var totalBytes: Int64 = 0
        var isIncomparable = false
    }

    nonisolated static func contents(current: SnapshotStore) throws -> [DiffEntry] {
        try rootSummaries(in: current).map { path, summary in
            DiffEntry(
                relativePath: path,
                isDirectory: summary.isDirectory,
                kind: summary.isIncomparable ? .incomparable : .added,
                baseSize: nil,
                currentSize: summary.totalBytes,
                delta: summary.totalBytes
            )
        }
        .sorted(by: sizeDescending)
    }

    nonisolated static func compare(base: SnapshotStore, current: SnapshotStore) throws -> [DiffEntry] {
        let baseMap = try rootSummaries(in: base)
        let currentMap = try rootSummaries(in: current)
        let keys = Set(baseMap.keys).union(currentMap.keys)
        return keys.compactMap { path in
            let b = baseMap[path]
            let c = currentMap[path]
            let isDirectory = c?.isDirectory ?? b?.isDirectory ?? false
            if (b?.isIncomparable ?? false) || (c?.isIncomparable ?? false) {
                return DiffEntry(relativePath: path, isDirectory: isDirectory, kind: .incomparable, baseSize: b?.totalBytes, currentSize: c?.totalBytes, delta: 0)
            }
            if b == nil, let c {
                return DiffEntry(relativePath: path, isDirectory: isDirectory, kind: .added, baseSize: nil, currentSize: c.totalBytes, delta: c.totalBytes)
            }
            if c == nil, let b {
                return DiffEntry(relativePath: path, isDirectory: isDirectory, kind: .removed, baseSize: b.totalBytes, currentSize: nil, delta: -b.totalBytes)
            }
            guard let b, let c else { return nil }
            let delta = c.totalBytes - b.totalBytes
            let kind: DiffKind
            if delta > 0 { kind = .grew }
            else if delta < 0 { kind = .shrunk }
            else { kind = .unchanged }
            return DiffEntry(relativePath: path, isDirectory: isDirectory, kind: kind, baseSize: b.totalBytes, currentSize: c.totalBytes, delta: delta)
        }
        .sorted(by: sizeDescending)
    }

    nonisolated private static func rootSummaries(in store: SnapshotStore) throws -> [String: RootSummary] {
        let rows = try store.allNodes()
        let rootIDs = Set(rows.compactMap { $0.node.parentId == nil ? $0.id : nil })
        var rootNameByNodeID: [Int64: String] = [:]
        var summaries: [String: RootSummary] = [:]

        for row in rows {
            guard let parentID = row.node.parentId else { continue }
            let rootName: String
            if rootIDs.contains(parentID) {
                rootName = row.node.name
            } else if let inherited = rootNameByNodeID[parentID] {
                rootName = inherited
            } else {
                continue
            }
            rootNameByNodeID[row.id] = rootName

            var summary = summaries[rootName] ?? RootSummary(isDirectory: row.node.isDirectory)
            if !row.node.isDirectory {
                summary.totalBytes += row.node.allocSize
            }
            if row.node.flags.contains(.denied) {
                summary.isIncomparable = true
            }
            summaries[rootName] = summary
        }
        return summaries
    }

    nonisolated private static func sizeDescending(_ lhs: DiffEntry, _ rhs: DiffEntry) -> Bool {
        let left = lhs.currentSize ?? lhs.baseSize ?? 0
        let right = rhs.currentSize ?? rhs.baseSize ?? 0
        if left == right {
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
        return left > right
    }
}
