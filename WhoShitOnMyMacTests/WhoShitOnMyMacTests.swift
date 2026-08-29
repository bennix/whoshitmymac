//
//  WhoShitOnMyMacTests.swift
//  WhoShitOnMyMacTests
//

import Foundation
import Testing
@testable import WhoShitOnMyMac

struct WhoShitOnMyMacTests {
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

    @Test func removedAndMissingApplicationsDisappearFromList() {
        let present = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Present.app"),
            name: "Present",
            bundleId: "com.example.present",
            bytes: 10,
            isRunning: false
        )
        let trashed = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Trashed.app"),
            name: "Trashed",
            bundleId: "com.example.trashed",
            bytes: 20,
            isRunning: false
        )
        let externallyRemoved = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Missing.app"),
            name: "Missing",
            bundleId: "com.example.missing",
            bytes: 30,
            isRunning: false
        )

        let remaining = AppState.remainingInstalledApps(
            [present, trashed, externallyRemoved],
            afterRemoving: [trashed.url],
            fileExists: { $0 != externallyRemoved.url.path }
        )

        #expect(remaining == [present])
    }

    @Test func forceQuitMatchingRequiresExactBundleAndApplicationPath() {
        let target = URL(fileURLWithPath: "/Applications/Example.app")
        #expect(AppProcessController.matches(
            bundleIdentifier: "com.example.utility",
            appURL: target,
            candidateBundleIdentifier: "com.example.utility",
            candidateBundleURL: target
        ))
        #expect(!AppProcessController.matches(
            bundleIdentifier: "com.example.utility",
            appURL: target,
            candidateBundleIdentifier: "com.example.other",
            candidateBundleURL: target
        ))
        #expect(!AppProcessController.matches(
            bundleIdentifier: "com.example.utility",
            appURL: target,
            candidateBundleIdentifier: "com.example.utility",
            candidateBundleURL: URL(fileURLWithPath: "/Users/test/Applications/Example.app")
        ))
    }
}
