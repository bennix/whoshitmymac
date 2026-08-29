import Foundation
import Testing
@testable import WhoShitOnMyMac

struct SnapshotStoreTests {
    @Test func relativePathJoinsParentAndName() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wsom-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SnapshotStore.create(at: url)
        try store.insert(
            SnapshotNode(parentId: nil, name: "", isDirectory: true, size: 0, allocSize: 0, mtime: 0, inode: 1, flags: []),
            id: 1
        )
        try store.insert(
            SnapshotNode(parentId: 1, name: "a.txt", isDirectory: false, size: 12, allocSize: 12, mtime: 0, inode: 2, flags: []),
            id: 2
        )
        #expect(try store.relativePath(id: 2) == "a.txt")
        let nodes = try store.allNodes()
        #expect(nodes.count == 2)
    }

    @Test func batchInsertHandlesLargeSnapshotsWithoutPerRowTransactions() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wsom-batch-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SnapshotStore.create(at: url)
        let started = Date()
        try store.beginBatch()
        for id in 1...20_000 {
            try store.insert(
                SnapshotNode(
                    parentId: id == 1 ? nil : 1,
                    name: id == 1 ? "" : "file-\(id)",
                    isDirectory: id == 1,
                    size: 1,
                    allocSize: 1,
                    mtime: 0,
                    inode: UInt64(id),
                    flags: []
                ),
                id: Int64(id)
            )
        }
        try store.endBatch()

        #expect(Date().timeIntervalSince(started) < 5)
        #expect(try store.allNodes().count == 20_000)
    }
}
