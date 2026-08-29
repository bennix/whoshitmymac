import Foundation
import Testing
@testable import WhoShitOnMyMac

struct SnapshotEngineTests {
    @Test func scansFilesAndDoesNotFollowSymlinkOutOfRoot() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("wsom-scan-\(UUID().uuidString)")
        let outside = fm.temporaryDirectory.appendingPathComponent("wsom-out-\(UUID().uuidString)")
        defer {
            try? fm.removeItem(at: root)
            try? fm.removeItem(at: outside)
        }
        try fm.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try "hello".write(to: root.appendingPathComponent("a/b.txt"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try "secret".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(
            at: root.appendingPathComponent("link-out"),
            withDestinationURL: outside
        )

        let db = fm.temporaryDirectory.appendingPathComponent("wsom-scan-\(UUID().uuidString).sqlite")
        defer { try? fm.removeItem(at: db) }
        let store = try SnapshotStore.create(at: db)
        var updates: [SnapshotScanProgress] = []
        let result = try SnapshotEngine().scan(
            root: root,
            into: store,
            progress: { updates.append($0) },
            shouldCancel: { false }
        )
        #expect(result.incomplete == false)
        #expect(result.fileCount >= 2)
        let paths = try store.allNodes().map { try store.relativePath(id: $0.id) }
        #expect(paths.contains("a/b.txt"))
        #expect(!paths.contains(where: { $0.contains("secret.txt") }))
        let flags = try store.allNodes().map(\.node.flags)
        #expect(flags.contains(where: { $0.contains(.symlink) }))
        #expect(updates.contains(where: { $0.phase == .counting }))
        #expect(updates.contains(where: { $0.phase == .scanning }))
        #expect(updates.first(where: { $0.phase == .scanning })?.totalItems == 3)
        #expect(updates.last?.phase == .finishing)
        #expect(updates.last?.fraction == 1)
    }

    @Test func cancelMarksIncomplete() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("wsom-cancel-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let db = fm.temporaryDirectory.appendingPathComponent("wsom-cancel-\(UUID().uuidString).sqlite")
        defer { try? fm.removeItem(at: db) }
        let store = try SnapshotStore.create(at: db)
        let result = try SnapshotEngine().scan(root: root, into: store, shouldCancel: { true })
        #expect(result.incomplete == true)
    }
}
