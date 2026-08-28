import Foundation

enum DiffKind: Equatable, Sendable {
    case added, removed, grew, shrunk, unchanged, incomparable
}

struct DiffEntry: Equatable, Sendable, Identifiable {
    var relativePath: String
    var kind: DiffKind
    var baseSize: Int64?
    var currentSize: Int64?
    var delta: Int64

    var id: String { relativePath }
}

enum DiffEngine {
    static func compare(base: SnapshotStore, current: SnapshotStore) throws -> [DiffEntry] {
        let baseMap = try base.pathMap()
        let currentMap = try current.pathMap()
        let keys = Set(baseMap.keys).union(currentMap.keys)
        return keys.sorted().compactMap { path in
            if path.isEmpty { return nil }
            let b = baseMap[path]
            let c = currentMap[path]
            if (b?.flags.contains(.denied) ?? false) || (c?.flags.contains(.denied) ?? false) {
                return DiffEntry(relativePath: path, kind: .incomparable, baseSize: b?.size, currentSize: c?.size, delta: 0)
            }
            if b == nil, let c {
                return DiffEntry(relativePath: path, kind: .added, baseSize: nil, currentSize: c.size, delta: c.size)
            }
            if c == nil, let b {
                return DiffEntry(relativePath: path, kind: .removed, baseSize: b.size, currentSize: nil, delta: -b.size)
            }
            guard let b, let c else { return nil }
            let delta = c.size - b.size
            let kind: DiffKind
            if delta > 0 { kind = .grew }
            else if delta < 0 { kind = .shrunk }
            else { kind = .unchanged }
            return DiffEntry(relativePath: path, kind: kind, baseSize: b.size, currentSize: c.size, delta: delta)
        }
    }
}
