import Foundation
import Testing
@testable import WhoShitOnMyMac

struct WeChatDuplicateFinderTests {
    @Test func titleParenthesesAreNotCopySuffix() {
        #expect(WeChatDuplicateFinder.isCopyFilename("授课计划（25健康大数据）2025-2026第一学期.doc") == false)
        #expect(WeChatDuplicateFinder.isCopyFilename("讲义.pdf") == false)
        #expect(WeChatDuplicateFinder.isCopyFilename("讲义(1).pdf") == true)
        #expect(WeChatDuplicateFinder.isCopyFilename("讲义（2）.pdf") == true)
        #expect(WeChatDuplicateFinder.isCopyFilename("协议(1).doc") == true)
    }

    @Test func sameMD5CopyIsTrashable() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("wsom-wx-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let payload = Data(repeating: 7, count: 128)
        try payload.write(to: root.appendingPathComponent("讲义.pdf"))
        try payload.write(to: root.appendingPathComponent("讲义(1).pdf"))
        try Data(repeating: 9, count: 64).write(to: root.appendingPathComponent("讲义(2).pdf"))
        try Data(repeating: 3, count: 80).write(to: root.appendingPathComponent("授课计划（25健康大数据）.doc"))
        try payload.write(to: root.appendingPathComponent("只有副本(1).pdf"))

        let copies = WeChatDuplicateFinder.findTrashableCopies(in: root)
        let names = Set(copies.map(\.url.lastPathComponent))
        #expect(names.contains("讲义(1).pdf"))
        #expect(names.contains("只有副本(1).pdf"))
        #expect(!names.contains("讲义.pdf"))
        #expect(!names.contains("讲义(2).pdf"))
        #expect(!names.contains("授课计划（25健康大数据）.doc"))
        #expect(copies.contains { $0.url.lastPathComponent == "讲义(1).pdf" && $0.originalURL.lastPathComponent == "讲义.pdf" })
    }

    @Test func junkEngineFindsWeChatCopiesUnderHome() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("wsom-wx-home-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let root = WeChatDuplicateFinder.defaultWeChatFilesRoot(home: home)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let payload = Data("wechat-original".utf8)
        try payload.write(to: root.appendingPathComponent("讲义.pdf"))
        try payload.write(to: root.appendingPathComponent("讲义(1).pdf"))

        let engine = JunkEngine(
            rules: [],
            home: home,
            now: Date(),
            isBusy: { _ in false },
            isInstalledBundle: { _ in false }
        )
        let items = engine.wechatDuplicateItems(blacklist: { _ in false }, whitelist: { _ in false })
        #expect(items.contains { $0.group == .wechatDupes && $0.path.lastPathComponent == "讲义(1).pdf" })
        #expect(items.contains { $0.detail.contains("讲义.pdf") })
    }
}
