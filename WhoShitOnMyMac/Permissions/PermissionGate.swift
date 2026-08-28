import AppKit
import Foundation

struct PermissionStatus: Equatable, Sendable {
    var hasFullDiskAccess: Bool
    var hasAppManagement: Bool
}

protocol FileReadable: Sendable {
    func isReadable(_ url: URL) -> Bool
}

struct FileManagerReadable: FileReadable {
    func isReadable(_ url: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: url.path)
    }
}

struct PermissionGate: Sendable {
    var probe: FileReadable
    var fdaProbeURL: URL
    var appManagementProbe: @Sendable () -> Bool

    static var `default`: PermissionGate {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return PermissionGate(
            probe: FileManagerReadable(),
            fdaProbeURL: home.appendingPathComponent("Library/Safari"),
            appManagementProbe: {
                FileManager.default.isReadableFile(atPath: "/Applications")
            }
        )
    }

    func status() -> PermissionStatus {
        PermissionStatus(
            hasFullDiskAccess: probe.isReadable(fdaProbeURL),
            hasAppManagement: appManagementProbe()
        )
    }

    func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    func openAppManagementSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")
    }

    private func open(_ spec: String) {
        guard let url = URL(string: spec) else { return }
        NSWorkspace.shared.open(url)
    }
}
