import Foundation
import Testing
@testable import WhoShitOnMyMac

struct BlacklistTests {
    private var support: URL {
        URL(fileURLWithPath: "/tmp/wsom-as")
    }

    @Test func systemPathIsBlocked() {
        #expect(Blacklist.blocks(
            URL(fileURLWithPath: "/System/Applications/Finder.app"),
            appSupport: support
        ))
    }

    @Test func usrBinIsBlocked() {
        #expect(Blacklist.blocks(URL(fileURLWithPath: "/usr/bin/swift"), appSupport: support))
    }

    @Test func appleBundleIdIsBlocked() {
        #expect(Blacklist.blocksBundleId("com.apple.finder"))
    }

    @Test func ownBundleIdIsBlocked() {
        #expect(Blacklist.blocksBundleId("fudan.WhoShitOnMyMac"))
    }

    @Test func appSupportSubtreeIsBlocked() {
        #expect(Blacklist.blocks(support.appendingPathComponent("snapshots/x.sqlite"), appSupport: support))
    }

    @Test func userAppIsNotBlockedByPath() {
        #expect(!Blacklist.blocks(URL(fileURLWithPath: "/Applications/Demo.app"), appSupport: support))
    }

    @Test func standardizesParentReferences() {
        let url = PathNormalizer.resolve(URL(fileURLWithPath: "/tmp/foo/../bar"))
        #expect(url.path == "/tmp/bar")
    }
}
