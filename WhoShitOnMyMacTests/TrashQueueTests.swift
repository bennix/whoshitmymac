import Foundation
import Testing
@testable import WhoShitOnMyMac

struct TrashQueueTests {
    @Test func blacklistRejectsEnqueue() {
        var queue = TrashQueue()
        let support = URL(fileURLWithPath: "/tmp/wsom-as")
        let result = queue.enqueue(
            TrashTask(url: URL(fileURLWithPath: "/System/Library/foo"), bytes: 1, source: "test"),
            appSupport: support,
            whitelist: { _ in false }
        )
        #expect(result == .blacklisted)
        #expect(queue.dryRun().isEmpty)
    }

    @Test func whitelistRejectsEnqueue() {
        var queue = TrashQueue()
        let keep = URL(fileURLWithPath: "/tmp/keep")
        let result = queue.enqueue(
            TrashTask(url: keep, bytes: 1, source: "test"),
            appSupport: URL(fileURLWithPath: "/tmp/wsom-as"),
            whitelist: { $0.path == keep.path }
        )
        #expect(result == .whitelisted)
    }

    @Test func executeContinuesAfterFailure() {
        var queue = TrashQueue()
        let a = URL(fileURLWithPath: "/tmp/a-\(UUID().uuidString)")
        let b = URL(fileURLWithPath: "/tmp/b-\(UUID().uuidString)")
        #expect(queue.enqueue(TrashTask(url: a, bytes: 1, source: "t"), appSupport: URL(fileURLWithPath: "/tmp/wsom-as"), whitelist: { _ in false }) == nil)
        #expect(queue.enqueue(TrashTask(url: b, bytes: 1, source: "t"), appSupport: URL(fileURLWithPath: "/tmp/wsom-as"), whitelist: { _ in false }) == nil)
        var trashed: [URL] = []
        let runner = TrashRunner { url in
            if url == a { throw NSError(domain: "test", code: 1) }
            trashed.append(url)
        }
        let outcome = runner.execute(queue)
        #expect(outcome.ok == 1)
        #expect(outcome.failed.count == 1)
        #expect(trashed == [b])
    }
}
