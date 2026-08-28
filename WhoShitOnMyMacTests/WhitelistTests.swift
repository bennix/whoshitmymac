import Foundation
import Testing
@testable import WhoShitOnMyMac

struct WhitelistTests {
    @Test func addedPathIsContained() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wsom-wl-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = WhitelistStore(fileURL: file)
        let keep = URL(fileURLWithPath: "/tmp/keep-me")
        try store.add(keep)
        #expect(store.contains(keep))
        #expect(!store.contains(URL(fileURLWithPath: "/tmp/other")))
    }

    @Test func globMatches() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wsom-wl-glob-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = WhitelistStore(fileURL: file)
        try store.addPattern("/tmp/protected-*")
        #expect(store.contains(URL(fileURLWithPath: "/tmp/protected-data")))
        #expect(!store.contains(URL(fileURLWithPath: "/tmp/unrelated")))
    }
}
