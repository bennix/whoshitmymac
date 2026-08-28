import Foundation
import Testing
@testable import WhoShitOnMyMac

private struct FakeReadable: FileReadable {
    var readable: Set<String>
    func isReadable(_ url: URL) -> Bool {
        readable.contains(url.path)
    }
}

struct PermissionGateTests {
    @Test func missingSafariMeansNoFullDiskAccess() {
        let safari = URL(fileURLWithPath: "/Users/test/Library/Safari")
        let gate = PermissionGate(
            probe: FakeReadable(readable: []),
            fdaProbeURL: safari,
            appManagementProbe: { true }
        )
        #expect(gate.status().hasFullDiskAccess == false)
        #expect(gate.status().hasAppManagement == true)
    }

    @Test func readableSafariMeansFullDiskAccess() {
        let safari = URL(fileURLWithPath: "/Users/test/Library/Safari")
        let gate = PermissionGate(
            probe: FakeReadable(readable: [safari.path]),
            fdaProbeURL: safari,
            appManagementProbe: { false }
        )
        #expect(gate.status().hasFullDiskAccess == true)
        #expect(gate.status().hasAppManagement == false)
    }
}
