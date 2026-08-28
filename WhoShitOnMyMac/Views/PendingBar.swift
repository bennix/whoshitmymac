import SwiftUI

struct PendingBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack {
            Text("待删除 \(state.queue.tasks.count) 项 · \(ByteFormat.string(state.queue.totalBytes))")
            Spacer()
            Button("查看计划") { state.showDryRun = true }
                .disabled(state.isTrashing)
            Button {
                state.runTrash()
            } label: {
                if state.isTrashing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("移到废纸篓")
                }
            }
            .disabled(state.isTrashing || state.queue.tasks.isEmpty)
        }
        .padding(10)
        .background(.bar)
    }
}

struct DryRunSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            Text("干跑计划").font(.title2)
            Text("以下路径将移到废纸篓，尚未改动磁盘。")
                .foregroundStyle(.secondary)
            List(state.queue.dryRun()) { task in
                VStack(alignment: .leading) {
                    Text(task.url.path)
                    Text("\(task.source) · \(ByteFormat.string(task.bytes))").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !state.lastExecuteFailed.isEmpty {
                Text("失败项").bold()
                ForEach(state.lastExecuteFailed, id: \.0.path) { item in
                    Text("\(item.0.path) — \(item.1)").foregroundStyle(.red).font(.caption)
                }
            }
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                Button("移到废纸篓") {
                    state.runTrash()
                }
                .disabled(state.isTrashing || state.queue.tasks.isEmpty)
            }
        }
        .padding()
        .frame(width: 640, height: 420)
        .onChange(of: state.isTrashing) { wasTrashing, isTrashing in
            if wasTrashing && !isTrashing && state.lastExecuteFailed.isEmpty {
                dismiss()
            }
        }
    }
}
