import Foundation
import Testing
@testable import WhoShitOnMyMac

struct DiffEngineTests {
    @Test func grewAddedAndIncomparable() throws {
        let fm = FileManager.default
        let baseURL = fm.temporaryDirectory.appendingPathComponent("wsom-diff-b-\(UUID().uuidString).sqlite")
        let currentURL = fm.temporaryDirectory.appendingPathComponent("wsom-diff-c-\(UUID().uuidString).sqlite")
        defer {
            try? fm.removeItem(at: baseURL)
            try? fm.removeItem(at: currentURL)
        }

        let base = try SnapshotStore.create(at: baseURL)
        try base.insert(SnapshotNode(parentId: nil, name: "", isDirectory: true, size: 0, allocSize: 0, mtime: 0, inode: 1, flags: []), id: 1)
        try base.insert(SnapshotNode(parentId: 1, name: "grew.txt", isDirectory: false, size: 10, allocSize: 10, mtime: 0, inode: 2, flags: []), id: 2)
        try base.insert(SnapshotNode(parentId: 1, name: "denied.txt", isDirectory: false, size: 1, allocSize: 1, mtime: 0, inode: 3, flags: [.denied]), id: 3)

        let current = try SnapshotStore.create(at: currentURL)
        try current.insert(SnapshotNode(parentId: nil, name: "", isDirectory: true, size: 0, allocSize: 0, mtime: 0, inode: 1, flags: []), id: 1)
        try current.insert(SnapshotNode(parentId: 1, name: "grew.txt", isDirectory: false, size: 20, allocSize: 20, mtime: 0, inode: 2, flags: []), id: 2)
        try current.insert(SnapshotNode(parentId: 1, name: "denied.txt", isDirectory: false, size: 1, allocSize: 1, mtime: 0, inode: 3, flags: []), id: 3)
        try current.insert(SnapshotNode(parentId: 1, name: "new.txt", isDirectory: false, size: 5, allocSize: 5, mtime: 0, inode: 4, flags: []), id: 4)

        let entries = try DiffEngine.compare(base: base, current: current)
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.relativePath, $0) })
        #expect(byPath["grew.txt"]?.kind == .grew)
        #expect(byPath["grew.txt"]?.delta == 10)
        #expect(byPath["new.txt"]?.kind == .added)
        #expect(byPath["denied.txt"]?.kind == .incomparable)
    }
}
