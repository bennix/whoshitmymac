import SwiftUI

struct SettingsPane: View {
    @Environment(AppState.self) private var state
    @AppStorage("allowPermanentDelete") private var allowPermanentDelete = false
    @AppStorage("refreshDock") private var refreshDock = false

    var body: some View {
        @Bindable var state = state
        Form {
            Section("权限") {
                LabeledContent("完全磁盘访问", value: state.permissionStatus.hasFullDiskAccess ? "已授予" : "未授予")
                LabeledContent("应用管理", value: state.permissionStatus.hasAppManagement ? "可用" : "需检查")
                Button("打开完全磁盘访问") { state.permission.openFullDiskAccessSettings() }
                Button("打开应用管理") { state.permission.openAppManagementSettings() }
                Button("重新检测") { state.refreshPermissions() }
            }
            Section("删除") {
                Toggle("彻底删除（默认关，危险）", isOn: $allowPermanentDelete)
                Toggle("卸载后刷新 Dock", isOn: $refreshDock)
                Text("第一期执行仍只进废纸篓。彻底删除开关仅作标记，避免误开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("白名单") {
                TextField("添加保护路径或 glob", text: $state.whitelistDraft)
                Button("加入白名单") {
                    let text = state.whitelistDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    try? state.whitelist.addPattern(text)
                    state.whitelistDraft = ""
                }
                ForEach(state.whitelist.patterns, id: \.self) { pattern in
                    HStack {
                        Text(pattern)
                        Spacer()
                        Button("移除") { try? state.whitelist.remove(pattern) }
                    }
                }
            }
            Section("操作历史") {
                let lines = OperationLog(fileURL: AppPaths.operationsLog).readLines().suffix(20)
                if lines.isEmpty {
                    Text("暂无记录").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(lines), id: \.self) { line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            Section("本应用数据") {
                Text(AppPaths.applicationSupport.path).font(.caption)
                Button("删除本应用数据目录") {
                    try? FileManager.default.removeItem(at: AppPaths.applicationSupport)
                    state.lastMessage = "已删除默认数据目录。若快照迁到别处，需手动删除。"
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
