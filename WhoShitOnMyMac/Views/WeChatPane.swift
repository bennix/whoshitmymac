import SwiftUI

struct WeChatPane: View {
    @Environment(AppState.self) private var state

    private var items: [JunkItem] {
        state.junkItems.filter { $0.group == .wechatDupes }
    }

    private var selectedCount: Int {
        items.filter { state.selectedJunk.contains($0.id) && $0.skipReason == .none }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("微信括号副本")
                .font(.title2)
            Text("只处理 `xwechat_files` 里文件名末尾带 (1)/(2) 的附件，并且 MD5 与某份无括号原件相同。标题中间的中文括号（如「（25健康大数据）」）不算副本。勾选后点「删除所选副本」，只进废纸篓。建议先退出微信再删除。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("扫描微信副本") { state.scanWeChatDuplicates() }
                    .disabled(state.isScanningWeChat)
                Button("全选副本") { state.selectAllWeChatDupes() }
                    .disabled(state.isScanningWeChat || items.isEmpty)
                Button("全不选") { state.clearWeChatSelection() }
                    .disabled(state.isScanningWeChat || selectedCount == 0)
                Button("删除所选副本") { state.trashSelectedWeChatDupes() }
                    .disabled(state.isScanningWeChat || state.isTrashing || selectedCount == 0)
                    .help("只把已勾选的微信副本移到废纸篓，不影响其他待删除项")
                if state.isScanningWeChat {
                    ProgressView().controlSize(.small)
                    Text("正在比对 MD5…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if state.isTrashing {
                    ProgressView().controlSize(.small)
                    Text("正在移到废纸篓…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let message = state.lastMessage {
                Text(message).foregroundStyle(.secondary)
            }

            if items.isEmpty, !state.isScanningWeChat {
                ContentUnavailableView(
                    "还没有扫描结果",
                    systemImage: "message",
                    description: Text("点「扫描微信副本」。没有全盘访问时可能扫不全容器。")
                )
            } else {
                List(items) { item in
                    HStack {
                        Toggle("", isOn: binding(item))
                            .labelsHidden()
                            .disabled(item.skipReason != .none)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.path.lastPathComponent)
                            if !item.detail.isEmpty {
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(item.path.deletingLastPathComponent().path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(ByteFormat.string(item.bytes))
                    }
                }
            }
        }
        .padding()
    }

    private func binding(_ item: JunkItem) -> Binding<Bool> {
        Binding(
            get: { state.selectedJunk.contains(item.id) },
            set: { on in
                state.setJunkSelected(item, selected: on, source: "微信")
            }
        )
    }
}
