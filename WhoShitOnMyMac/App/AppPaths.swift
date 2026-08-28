import Foundation

enum AppPaths {
    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("WhoShitOnMyMac", isDirectory: true)
    }

    static var snapshotsDirectory: URL {
        applicationSupport.appendingPathComponent("snapshots", isDirectory: true)
    }

    static var whitelistFile: URL {
        applicationSupport.appendingPathComponent("whitelist.json")
    }

    static var operationsLog: URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return logs.appendingPathComponent("Logs/WhoShitOnMyMac/operations.log")
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
