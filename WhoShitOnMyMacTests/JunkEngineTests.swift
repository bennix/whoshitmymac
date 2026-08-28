import Foundation
import Testing
@testable import WhoShitOnMyMac

struct JunkEngineTests {
    @Test func scansCachesInstallersArtifactsAndOrphans() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("wsom-home-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }

        try fm.createDirectory(at: home.appendingPathComponent("Library/Caches/foo"), withIntermediateDirectories: true)
        try "c".write(to: home.appendingPathComponent("Library/Caches/foo/x"), atomically: true, encoding: .utf8)

        try fm.createDirectory(at: home.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        try Data([0, 1, 2]).write(to: home.appendingPathComponent("Downloads/a.dmg"))

        let nodeModules = home.appendingPathComponent("Projects/app/node_modules")
        try fm.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try "n".write(to: nodeModules.appendingPathComponent("pkg"), atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: nodeModules.path)

        try fm.createDirectory(at: home.appendingPathComponent("Library/Application Support/com.example.Gone"), withIntermediateDirectories: true)
        try "o".write(to: home.appendingPathComponent("Library/Application Support/com.example.Gone/d"), atomically: true, encoding: .utf8)

        let engine = JunkEngine(
            rules: JunkRule.bundledDefaults,
            home: home,
            now: Date(),
            isBusy: { _ in false },
            isInstalledBundle: { _ in false }
        )
        let items = engine.scan(blacklist: { _ in false }, whitelist: { _ in false })
        #expect(items.contains { $0.group == .caches && $0.selectedByDefault == false })
        #expect(items.contains { $0.group == .installers && $0.path.lastPathComponent == "a.dmg" })
        #expect(items.contains { $0.group == .artifacts && $0.skipReason == .recentActivity })
        #expect(items.contains { $0.group == .orphans && $0.path.lastPathComponent == "com.example.Gone" })
    }
}
