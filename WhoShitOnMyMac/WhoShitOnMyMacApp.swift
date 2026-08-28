//
//  WhoShitOnMyMacApp.swift
//  WhoShitOnMyMac
//

import SwiftData
import SwiftUI

@main
struct WhoShitOnMyMacApp: App {
    @State private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([SnapshotRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .defaultSize(width: 960, height: 640)
        .modelContainer(sharedModelContainer)
    }
}
