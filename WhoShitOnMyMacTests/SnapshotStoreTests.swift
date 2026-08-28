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
}
