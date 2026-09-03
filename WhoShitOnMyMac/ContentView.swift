import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SnapshotRecord.createdAt, order: .reverse) private var snapshots: [SnapshotRecord]

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $state.sidebar) { item in
                Text(item.rawValue).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            VStack(spacing: 0) {
                if !state.permissionStatus.hasFullDiskAccess {
                    PermissionBanner()
                }
                Group {
                    switch state.sidebar {
                    case .snapshots:
                        SnapshotPane(snapshots: snapshots)
                    case .junk:
                        JunkPane()
                    case .wechat:
                        WeChatPane()
                    case .apps:
                        AppsPane()
                    case .settings:
                        SettingsPane()
                    }
                }
                if !state.queue.tasks.isEmpty {
                    PendingBar()
                }
            }
        }
        .sheet(isPresented: $state.showDryRun) {
            DryRunSheet()
        }
        .sheet(isPresented: $state.showOnboarding) {
            PermissionOnboarding()
        }
        .onAppear {
            state.refreshPermissions()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .modelContainer(for: SnapshotRecord.self, inMemory: true)
}
