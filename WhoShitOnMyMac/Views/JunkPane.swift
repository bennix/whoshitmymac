import SwiftUI

struct JunkPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("扫描垃圾") { state.scanJunk() }
                Button("全不选") { state.selectedJunk = [] }
                Spacer()
            }
            List {
                ForEach(JunkGroup.allCases, id: \.self) { group in
                    let items = state.junkItems.filter { $0.group == group }
                    if !items.isEmpty {
                        Section(header: Text(title(group))) {
                            ForEach(items) { item in
                                HStack {
                                    Toggle("", isOn: binding(item))
                                        .labelsHidden()
                                        .disabled(item.skipReason != .none && item.skipReason != .recentActivity)
                                    VStack(alignment: .leading) {
                                        Text(item.path.path)
                                        if item.skipReason != .none {
                                            Text(skipText(item.skipReason)).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(ByteFormat.string(item.bytes))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }

    // JunkGroup is CaseIterable on the enum.

    private func title(_ group: JunkGroup) -> String {
        switch group {
        case .caches: return "用户缓存"
        case .logs: return "日志"
        case .trash: return "废纸篓"
        case .browsers: return "浏览器"
        case .devCaches: return "开发工具缓存"
        case .orphans: return "孤儿残留"
        case .installers: return "安装包"
        case .artifacts: return "工程产物"
        case .sensitive: return "备份 / 敏感（请谨慎）"
        }
    }

    private func skipText(_ reason: SkipReason) -> String {
        switch reason {
        case .none: return ""
        case .busy: return "占用中，已跳过"
        case .whitelist: return "白名单"
        case .blacklist: return "黑名单"
        case .unproven: return "无法证明可删"
        case .recentActivity: return "7 天内有活动，默认不选"
        }
    }

    private func binding(_ item: JunkItem) -> Binding<Bool> {
        Binding(
            get: { state.selectedJunk.contains(item.id) },
            set: { on in
                if on {
                    state.selectedJunk.insert(item.id)
                    state.enqueue(url: item.path, bytes: item.bytes, source: "垃圾")
                } else {
                    state.selectedJunk.remove(item.id)
                }
            }
        )
    }
}
