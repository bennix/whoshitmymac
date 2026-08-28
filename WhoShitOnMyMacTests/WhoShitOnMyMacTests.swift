//
//  WhoShitOnMyMacTests.swift
//  WhoShitOnMyMacTests
//

import Foundation
import Testing
@testable import WhoShitOnMyMac

struct WhoShitOnMyMacTests {
    @Test func snapshotIncompleteCannotBeBase() {
        let record = SnapshotRecord(
            rootPath: "/tmp",
            incomplete: true
        )
        #expect(SnapshotSelection.canBeBase(record) == false)
    }

    @Test func snapshotCompleteCanBeBase() {
        let record = SnapshotRecord(
            rootPath: "/tmp",
            incomplete: false
        )
        #expect(SnapshotSelection.canBeBase(record) == true)
    }

    @Test func installedAppsAppearBeforeSizeCalculation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wsom-apps-\(UUID().uuidString)")
        let contents = root.appendingPathComponent("Example.app/Contents")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.utility",
            "CFBundleName": "Example Utility",
            "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        let apps = AppState.discoverInstalledApps(
            in: [root],
            runningBundleIDs: ["com.example.utility"]
        )
        #expect(apps.count == 1)
        #expect(apps.first?.name == "Example Utility")
        #expect(apps.first?.bytes == nil)
        #expect(apps.first?.isRunning == true)
    }
}
