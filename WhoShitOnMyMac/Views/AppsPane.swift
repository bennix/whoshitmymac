import AppKit
import SwiftUI

struct AppsPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("刷新应用列表") { state.loadInstalledApps() }
                        .disabled(state.isLoadingApps)
                    if state.isLoadingApps {
                        ProgressView()
                            .controlSize(.small)
                        Text(state.appLoadProgress)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button("检查应用管理权限") { state.permission.openAppManagementSettings() }
                        .help("部分应用受 macOS 应用管理权限保护")
                    Spacer()
                    if !state.isLoadingApps {
                        Text("\(state.installedApps.count) 个应用")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Group {
                    if state.installedApps.isEmpty && !state.isLoadingApps {
                        ContentUnavailableView {
                            Label("未找到应用", systemImage: "app.dashed")
                        } description: {
                            Text("应用列表读取自 /Applications 和 ~/Applications")
                        }
                    } else {
                        List(state.installedApps, selection: Binding(
                            get: { state.selectedApp },
                            set: { app in
                                if let app {
                                    state.makeUninstallPlan(for: app)
                                }
                            }
                        )) { app in
                            HStack {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                VStack(alignment: .leading) {
                                    Text(app.name)
                                    Text(app.bundleId).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if app.isRunning {
                                    Text("需先退出").font(.caption).foregroundStyle(.orange)
                                }
                                if let bytes = app.bytes {
                                    Text(ByteFormat.string(bytes))
                                        .monospacedDigit()
                                } else {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .help("正在计算应用体积")
                                }
                            }
                            .tag(app)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 10) {
                if let plan = state.uninstallPlan {
                    if plan.blocked {
                        Text(plan.blockReason ?? "不可卸载").foregroundStyle(.red)
                    } else {
                        Text(plan.appURL.path).font(.caption)
                        List(plan.residues) { item in
                            HStack {
                                Toggle("", isOn: residueBinding(item))
                                    .labelsHidden()
                                    .disabled(item.match == .shared)
                                VStack(alignment: .leading) {
                                    Text(item.url.path)
                                    Text(item.reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("加入待删除") {
                            state.enqueue(url: plan.appURL, bytes: 0, source: "卸载")
                            for item in plan.residues where state.selectedResidues.contains(item.id) {
                                state.enqueue(url: item.url, bytes: 0, source: "卸载残留")
                            }
                        }
                        .disabled(state.selectedApp?.isRunning == true)
                    }
                } else {
                    Text("选择一个应用以预览残留").foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            state.pruneMissingInstalledApps()
            if state.installedApps.isEmpty { state.loadInstalledApps() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.pruneMissingInstalledApps()
        }
    }

    private func residueBinding(_ item: ResidueItem) -> Binding<Bool> {
        Binding(
            get: { state.selectedResidues.contains(item.id) },
            set: { on in
                if on { state.selectedResidues.insert(item.id) }
                else { state.selectedResidues.remove(item.id) }
            }
        )
    }
}
