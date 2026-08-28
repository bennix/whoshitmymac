import AppKit
import SwiftData
import SwiftUI

struct SnapshotPane: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var modelContext
    var snapshots: [SnapshotRecord]

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("新建扫描") { pickAndScan() }
                    .disabled(state.isScanning)
                Spacer()
            }
            if state.isScanning {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(state.scanProgress)
                            .font(.callout.weight(.medium))
                        Spacer()
                        if let fraction = state.scanFraction {
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let fraction = state.scanFraction {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    if !state.scanDetail.isEmpty {
                        Text(state.scanDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(state.scanProgress)
            }
            if let message = state.lastMessage {
                Text(message).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("扫描历史")
                            .font(.headline)
                        Spacer()
                        Text("\(snapshots.count) 次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    List(snapshots, selection: $state.currentSnapshotID) { record in
                        VStack(alignment: .leading) {
                            Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                            Text(record.rootPath).font(.caption).foregroundStyle(.secondary)
                            Text("\(ByteFormat.string(record.totalBytes)) · \(record.fileCount) 文件")
                                .font(.caption)
                            if record.incomplete {
                                Text("扫描不完整，部分内容可能缺失")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .tag(record.id)
                    }
                }
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340, maxHeight: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if state.isLoadingSnapshotEntries {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("正在汇总根目录内容…").foregroundStyle(.secondary)
                        }
                    }
                    if !visibleEntries.isEmpty {
                        HStack(spacing: 28) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(visibleEntries.count) 项")
                                        .font(.title2.weight(.semibold))
                                        .monospacedDigit()
                                    Text("疑似垃圾")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "trash.slash")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                            }
                            Divider()
                                .frame(height: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ByteFormat.string(suspectedBytes))
                                    .font(.title2.weight(.semibold))
                                    .monospacedDigit()
                                Text("预计可清理")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if !visibleEntries.isEmpty, let rootPath = currentRootPath {
                        HStack {
                            Text("扫描结果")
                                .font(.headline)
                            Spacer()
                            Button("全选") { state.selectAllDiffs(rootPath: rootPath) }
                                .disabled(selectableEntries.isEmpty || state.selectedDiffs.count == selectableEntries.count)
                            Button("取消全选") { state.clearDiffSelection() }
                                .disabled(state.selectedDiffs.isEmpty)
                        }
                    }
                    List(visibleEntries) { entry in
                        HStack {
                            if entry.currentSize != nil && entry.kind != .incomparable, currentRootPath != nil {
                                Toggle("", isOn: binding(for: entry))
                                    .labelsHidden()
                                    .help(state.selectedDiffs.contains(entry.id) ? "取消选择" : "选择并加入待删除")
                            }
                            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                            Text(entry.relativePath)
                                .lineLimit(1)
                            Spacer()
                            Text(label(for: entry))
                                .monospacedDigit()
                                .foregroundStyle(color(for: entry.kind))
                        }
                    }
                    if state.currentSnapshotID == nil && !state.isLoadingSnapshotEntries {
                        ContentUnavailableView {
                            Label("选择一次扫描", systemImage: "clock.arrow.circlepath")
                        } description: {
                            Text("从左侧扫描历史中选择记录，或新建扫描")
                        }
                    }
                    if state.currentSnapshotID != nil && visibleEntries.isEmpty && !state.isLoadingSnapshotEntries {
                        ContentUnavailableView {
                            Label("未发现疑似垃圾", systemImage: "checkmark.circle")
                        } description: {
                            Text("这次扫描没有可列出的清理候选项")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding()
        .onAppear {
            if state.currentSnapshotID == nil {
                state.currentSnapshotID = snapshots.first?.id
            }
        }
        .onChange(of: state.currentSnapshotID) { _, _ in
            loadCurrentContents()
        }
    }

    private var visibleEntries: [DiffEntry] {
        state.diffEntries.filter { $0.kind != .unchanged }
    }

    private var selectableEntries: [DiffEntry] {
        visibleEntries.filter { $0.currentSize != nil && $0.kind != .incomparable }
    }

    private var suspectedBytes: Int64 {
        visibleEntries.reduce(0) { $0 + ($1.currentSize ?? 0) }
    }

    private var currentRootPath: String? {
        guard let path = snapshots.first(where: { $0.id == state.currentSnapshotID })?.rootPath,
              path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    private func binding(for entry: DiffEntry) -> Binding<Bool> {
        Binding(
            get: { state.selectedDiffs.contains(entry.relativePath) },
            set: { on in
                if let rootPath = currentRootPath {
                    state.setDiffSelected(entry, rootPath: rootPath, selected: on)
                }
            }
        )
    }

    private func label(for entry: DiffEntry) -> String {
        switch entry.kind {
        case .added: return ByteFormat.string(entry.currentSize ?? 0)
        case .removed: return "删除"
        case .grew: return "\(ByteFormat.string(entry.currentSize ?? 0)) · +\(ByteFormat.string(entry.delta))"
        case .shrunk: return "\(ByteFormat.string(entry.currentSize ?? 0)) · \(ByteFormat.string(entry.delta))"
        case .incomparable: return "不可比较"
        case .unchanged: return ""
        }
    }

    private func color(for kind: DiffKind) -> Color {
        switch kind {
        case .added: return .primary
        case .grew: return .red
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
        state.scanProgress = "正在准备扫描…"
        state.scanFraction = nil
        state.scanDetail = root.path
        let sqliteName = "\(UUID().uuidString).sqlite"
        let sqliteURL = AppPaths.snapshotsDirectory.appendingPathComponent(sqliteName)
        let started = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let store = try SnapshotStore.create(at: sqliteURL)
                let result = try SnapshotEngine().scan(
                    root: root,
                    into: store,
                    progress: { progress in
                        DispatchQueue.main.async {
                            state.scanFraction = progress.fraction
                            state.scanProgress = switch progress.phase {
                            case .preparing: "正在准备扫描…"
                            case .counting: "正在计算文件数量…"
                            case .scanning: "已扫描 \(progress.fileCount) 个文件 · \(ByteFormat.string(progress.totalBytes))"
                            case .finishing: "正在保存快照…"
                            }
                            state.scanDetail = (progress.currentPath as NSString).abbreviatingWithTildeInPath
                        }
                    },
                    shouldCancel: { false }
                )
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
                    state.currentSnapshotID = record.id
                    state.isScanning = false
                    state.scanProgress = "完成"
                    state.scanFraction = 1
                    state.scanDetail = ""
                    state.lastMessage = result.incomplete ? "扫描不完整，部分内容可能缺失" : "扫描完成"
                    loadContents(record: record)
                }
            } catch {
                DispatchQueue.main.async {
                    state.isScanning = false
                    state.scanFraction = nil
                    state.scanDetail = ""
                    state.lastMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadCurrentContents() {
        guard let currentID = state.currentSnapshotID,
              let current = snapshots.first(where: { $0.id == currentID }) else { return }
        loadContents(record: current)
    }

    private func loadContents(record: SnapshotRecord) {
        state.clearDiffSelection()
        state.isLoadingSnapshotEntries = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let store = try SnapshotStore.create(at: AppPaths.snapshotsDirectory.appendingPathComponent(record.sqliteFileName))
                let entries = try DiffEngine.contents(current: store)
                DispatchQueue.main.async {
                    state.diffEntries = entries
                    state.isLoadingSnapshotEntries = false
                }
            } catch {
                DispatchQueue.main.async {
                    state.isLoadingSnapshotEntries = false
                    state.lastMessage = error.localizedDescription
                }
            }
        }
    }
}
