import Foundation
import Testing
@testable import WhoShitOnMyMac

struct UninstallEngineTests {
    @Test func dummyBundleStrongMatch() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("wsom-un-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let support = home.appendingPathComponent("Library/Application Support/com.example.Dummy")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let app = URL(fileURLWithPath: "/Applications/Dummy.app")
        let plan = UninstallEngine.plan(
            appURL: app,
            bundleId: "com.example.Dummy",
            displayName: "Dummy",
            home: home,
            otherInstalledIds: []
        )
        #expect(plan.blocked == false)
        #expect(plan.residues.contains { $0.match == .strong && $0.url.path.hasSuffix("com.example.Dummy") && $0.selectedByDefault })
        #expect(!plan.residues.contains { $0.url.path.hasPrefix("/System") })
    }

    @Test func appleFinderIsBlocked() {
        let plan = UninstallEngine.plan(
            appURL: URL(fileURLWithPath: "/System/Applications/Finder.app"),
            bundleId: "com.apple.finder",
            displayName: "Finder",
            home: URL(fileURLWithPath: "/tmp"),
            otherInstalledIds: []
        )
        #expect(plan.blocked)
        #expect(plan.residues.isEmpty)
    }

    @Test func sharedWhenAnotherCopyInstalled() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("wsom-un2-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let group = home.appendingPathComponent("Library/Group Containers/group.com.example.Dummy")
        try fm.createDirectory(at: group, withIntermediateDirectories: true)
        let plan = UninstallEngine.plan(
            appURL: URL(fileURLWithPath: "/Applications/Dummy.app"),
            bundleId: "com.example.Dummy",
            displayName: "Dummy",
            home: home,
            otherInstalledIds: ["com.example.Dummy"]
        )
        #expect(plan.residues.contains { $0.match == .shared && $0.selectedByDefault == false })
    }

    @Test func shortOrLocalNameDoesNotCreateDotConfig() {
        let home = URL(fileURLWithPath: "/Users/test")
        let plan = UninstallEngine.plan(
            appURL: URL(fileURLWithPath: "/Applications/Do.app"),
            bundleId: "com.example.Do",
            displayName: "Do",
            home: home,
            otherInstalledIds: []
        )
        #expect(!plan.residues.contains { $0.url.path.contains("/.config") })
        let local = UninstallEngine.plan(
            appURL: URL(fileURLWithPath: "/Applications/Local.app"),
            bundleId: "com.example.LocalApp",
            displayName: "Local",
            home: home,
            otherInstalledIds: []
        )
        #expect(!local.residues.contains { $0.url.path == "/Users/test/.config" || $0.url.path == "/Users/test/.local" })
    }

    @Test func invalidBundleIdDoesNotScanLibrary() {
        #expect(!UninstallEngine.isValidBundleId("com.*.evil"))
        #expect(!UninstallEngine.isValidBundleId("not-dns"))
        let plan = UninstallEngine.plan(
            appURL: URL(fileURLWithPath: "/Applications/Weird.app"),
            bundleId: "com.*.evil",
            displayName: "Weird",
            home: URL(fileURLWithPath: "/Users/test"),
            otherInstalledIds: []
        )
        #expect(!plan.residues.contains { $0.url.path.contains("/Library/") })
    }

    @Test func relatedHelpersAreShownAsConfirmableResidues() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("wsom-helper-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let systemLibrary = root.appendingPathComponent("Library")
        let config = home.appendingPathComponent(".config/com.vortex.helper")
        let daemon = systemLibrary.appendingPathComponent("LaunchDaemons/com.vortex.helper.plist")
        try fm.createDirectory(at: config, withIntermediateDirectories: true)
        try fm.createDirectory(at: daemon.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: daemon)

        let plan = UninstallEngine.plan(
            appURL: URL(fileURLWithPath: "/Applications/星连VPN.app"),
            bundleId: "org.erb.vortex",
            displayName: "星连VPN",
            home: home,
            otherInstalledIds: [],
            systemLibrary: systemLibrary
        )

        #expect(plan.residues.contains {
            PathNormalizer.resolve($0.url).path == PathNormalizer.resolve(config).path
                && $0.match == .nameVariant && !$0.selectedByDefault
        })
        #expect(plan.residues.contains {
            PathNormalizer.resolve($0.url).path == PathNormalizer.resolve(daemon).path
                && $0.match == .nameVariant && !$0.selectedByDefault
        })
    }
}
