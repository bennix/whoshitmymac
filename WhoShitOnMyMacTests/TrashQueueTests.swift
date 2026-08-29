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
        #expect(outcome.succeeded == [b])
        #expect(outcome.failed.count == 1)
        #expect(trashed == [b])
    }

    @Test func administratorRetryOnlyAcceptsTopLevelApplications() {
        #expect(AdministratorTrashRunner.canHandle(TrashTask(url: URL(fileURLWithPath: "/Applications/Example.app"), bytes: 0, source: "卸载")))
        #expect(!AdministratorTrashRunner.canHandle(TrashTask(url: URL(fileURLWithPath: "/Applications/Folder/Example.app"), bytes: 0, source: "卸载")))
        #expect(!AdministratorTrashRunner.canHandle(TrashTask(url: URL(fileURLWithPath: "/Users/test/Example.app"), bytes: 0, source: "卸载")))
        #expect(!AdministratorTrashRunner.canHandle(TrashTask(url: URL(fileURLWithPath: "/Applications/readme.txt"), bytes: 0, source: "卸载")))
        #expect(!AdministratorTrashRunner.canHandle(TrashTask(url: URL(fileURLWithPath: "/System/Applications/Finder.app"), bytes: 0, source: "卸载")))
        #expect(AdministratorTrashRunner.canHandle(TrashTask(url: URL(fileURLWithPath: "/Library/LaunchDaemons/com.example.helper.plist"), bytes: 0, source: "卸载残留")))
        #expect(!AdministratorTrashRunner.canHandle(TrashTask(url: URL(fileURLWithPath: "/Library/LaunchDaemons/com.example.helper.plist"), bytes: 0, source: "垃圾")))
    }

    @Test func administratorRetryStopsLaunchJobsBeforeMovingApplication() {
        let app = TrashTask(url: URL(fileURLWithPath: "/Applications/Example.app"), bytes: 0, source: "卸载")
        let support = TrashTask(url: URL(fileURLWithPath: "/Library/Application Support/Example"), bytes: 0, source: "卸载残留")
        let agent = TrashTask(url: URL(fileURLWithPath: "/Library/LaunchAgents/com.example.agent.plist"), bytes: 0, source: "卸载残留")
        let daemon = TrashTask(url: URL(fileURLWithPath: "/Library/LaunchDaemons/com.example.daemon.plist"), bytes: 0, source: "卸载残留")

        let ordered = AdministratorTrashRunner.orderedTasks([support, app, agent, daemon])

        #expect(ordered.map(\.url.path) == [agent.url.path, daemon.url.path, app.url.path, support.url.path])
    }
}
