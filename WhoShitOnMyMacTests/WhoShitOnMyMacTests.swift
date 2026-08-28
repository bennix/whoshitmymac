//
//  WhoShitOnMyMacTests.swift
//  WhoShitOnMyMacTests
//

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
}
