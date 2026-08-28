import Foundation
import Testing
@testable import WhoShitOnMyMac

@MainActor
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

    @Test func rootFoldersUseRecursiveTotalsAndSortBySize() throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("wsom-root-total-\(UUID().uuidString).sqlite")
        defer { try? fm.removeItem(at: url) }

        let store = try SnapshotStore.create(at: url)
        try store.insert(SnapshotNode(parentId: nil, name: "", isDirectory: true, size: 0, allocSize: 0, mtime: 0, inode: 1, flags: []), id: 1)
        try store.insert(SnapshotNode(parentId: 1, name: "Small", isDirectory: true, size: 0, allocSize: 0, mtime: 0, inode: 2, flags: []), id: 2)
        try store.insert(SnapshotNode(parentId: 2, name: "one.bin", isDirectory: false, size: 10, allocSize: 12, mtime: 0, inode: 3, flags: []), id: 3)
        try store.insert(SnapshotNode(parentId: 1, name: "Large", isDirectory: true, size: 0, allocSize: 0, mtime: 0, inode: 4, flags: []), id: 4)
        try store.insert(SnapshotNode(parentId: 4, name: "nested", isDirectory: true, size: 0, allocSize: 0, mtime: 0, inode: 5, flags: []), id: 5)
        try store.insert(SnapshotNode(parentId: 5, name: "two.bin", isDirectory: false, size: 20, allocSize: 24, mtime: 0, inode: 6, flags: []), id: 6)
        try store.insert(SnapshotNode(parentId: 4, name: "three.bin", isDirectory: false, size: 30, allocSize: 32, mtime: 0, inode: 7, flags: []), id: 7)

        let entries = try DiffEngine.contents(current: store)
        let paths = entries.map(\.relativePath)
        let largeSize = entries.first { $0.relativePath == "Large" }?.currentSize
        let smallSize = entries.first { $0.relativePath == "Small" }?.currentSize
        let allDirectories = entries.allSatisfy(\.isDirectory)
        #expect(paths == ["Large", "Small"])
        #expect(largeSize == 56)
        #expect(smallSize == 12)
        #expect(allDirectories)
    }
}
