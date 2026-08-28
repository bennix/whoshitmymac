import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SnapshotPane: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var modelContext
    var snapshots: [SnapshotRecord]
    @State private var note = ""

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("新建扫描") { pickAndScan() }
                    .disabled(state.isScanning)
                Button("导入快照") { importSnapshot() }
                if state.isScanning {
                    ProgressView().controlSize(.small)
                    Text(state.scanProgress)
                }
                Spacer()
            }
            if let message = state.lastMessage {
                Text(message).foregroundStyle(.secondary)
            }
            HStack(alignment: .top) {
                List(snapshots) { record in
                    VStack(alignment: .leading) {
                        Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                        Text(record.rootPath).font(.caption).foregroundStyle(.secondary)
                        Text("\(ByteFormat.string(record.totalBytes)) · \(record.fileCount) 文件")
                            .font(.caption)
                        if record.incomplete {
                            Text("不完整，不能当基准").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .tag(record.id)
                    .contextMenu {
                        Button("设为基准") {
                            if SnapshotSelection.canBeBase(record) { state.baseSnapshotID = record.id }
                        }
                        .disabled(!SnapshotSelection.canBeBase(record))
                        Button("设为当前") { state.currentSnapshotID = record.id }
                    }
                }
                .frame(minWidth: 240)
                VStack(alignment: .leading) {
                    Picker("基准", selection: $state.baseSnapshotID) {
                        Text("未选").tag(Optional<UUID>.none)
                        ForEach(snapshots.filter { SnapshotSelection.canBeBase($0) }) { record in
                            Text(record.createdAt.formatted()).tag(Optional(record.id))
                        }
                    }
                    Picker("当前", selection: $state.currentSnapshotID) {
                        Text("未选").tag(Optional<UUID>.none)
                        ForEach(snapshots) { record in
                            Text(record.createdAt.formatted()).tag(Optional(record.id))
                        }
                    }
                    Button("对比") { compare() }
                        .disabled(state.baseSnapshotID == nil || state.currentSnapshotID == nil)
                    List(state.diffEntries.filter { $0.kind != .unchanged }) { entry in
                        HStack {
                            if entry.kind == .grew || entry.kind == .added {
                                Toggle("", isOn: binding(for: entry))
                                    .labelsHidden()
                            }
                            Text(entry.relativePath)
                            Spacer()
                            Text(label(for: entry))
                                .foregroundStyle(color(for: entry.kind))
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func binding(for entry: DiffEntry) -> Binding<Bool> {
        Binding(
            get: { state.selectedDiffs.contains(entry.relativePath) },
            set: { on in
                if on {
                    state.selectedDiffs.insert(entry.relativePath)
                    if let current = snapshots.first(where: { $0.id == state.currentSnapshotID }) {
                        let url = URL(fileURLWithPath: current.rootPath).appendingPathComponent(entry.relativePath)
                        state.enqueue(url: url, bytes: entry.currentSize ?? 0, source: "对比")
                    }
                } else {
                    state.selectedDiffs.remove(entry.relativePath)
                }
            }
        )
    }

    private func label(for entry: DiffEntry) -> String {
        switch entry.kind {
        case .added: return "新增 \(ByteFormat.string(entry.delta))"
        case .removed: return "删除"
        case .grew: return "+\(ByteFormat.string(entry.delta))"
        case .shrunk: return ByteFormat.string(entry.delta)
        case .incomparable: return "不可比较"
        case .unchanged: return ""
        }
    }

    private func color(for kind: DiffKind) -> Color {
        switch kind {
        case .added, .grew: return .red
        case .removed, .shrunk: return .green
        case .incomparable: return .secondary
        case .unchanged: return .primary
        }
    }

    private func pickAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan(root: url)
    }

    private func scan(root: URL) {
        state.isScanning = true
        state.scanProgress = "正在扫描…"
        let sqliteName = "\(UUID().uuidString).sqlite"
        let sqliteURL = AppPaths.snapshotsDirectory.appendingPathComponent(sqliteName)
        let started = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let store = try SnapshotStore.create(at: sqliteURL)
                let result = try SnapshotEngine().scan(root: root, into: store) { false }
                DispatchQueue.main.async {
                    let record = SnapshotRecord(
                        rootPath: root.path,
                        fileCount: result.fileCount,
                        totalBytes: result.totalBytes,
                        deniedCount: result.deniedCount,
                        elapsed: Date().timeIntervalSince(started),
                        incomplete: result.incomplete,
                        sqliteFileName: sqliteName
                    )
                    modelContext.insert(record)
                    try? modelContext.save()
                    state.isScanning = false
                    state.scanProgress = "完成"
                    state.lastMessage = result.incomplete ? "扫描不完整，不能当基准" : "扫描完成"
                }
            } catch {
                DispatchQueue.main.async {
                    state.isScanning = false
                    state.lastMessage = error.localizedDescription
                }
            }
        }
    }

    private func importSnapshot() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let dest = AppPaths.snapshotsDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.createDirectory(at: AppPaths.snapshotsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: url, to: dest)
        let record = SnapshotRecord(rootPath: "(导入)", sqliteFileName: dest.lastPathComponent)
        modelContext.insert(record)
    }

    private func compare() {
        guard let baseID = state.baseSnapshotID, let currentID = state.currentSnapshotID,
              let base = snapshots.first(where: { $0.id == baseID }),
              let current = snapshots.first(where: { $0.id == currentID }) else { return }
        do {
            let baseStore = try SnapshotStore.create(at: AppPaths.snapshotsDirectory.appendingPathComponent(base.sqliteFileName))
            let currentStore = try SnapshotStore.create(at: AppPaths.snapshotsDirectory.appendingPathComponent(current.sqliteFileName))
            state.diffEntries = try DiffEngine.compare(base: baseStore, current: currentStore)
                .sorted { abs($0.delta) > abs($1.delta) }
        } catch {
            state.lastMessage = error.localizedDescription
        }
    }
}
