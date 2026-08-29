import Darwin
import Foundation

struct TrashTask: Identifiable, Equatable, Sendable {
    var id: UUID
    var url: URL
    var bytes: Int64
    var source: String

    init(id: UUID = UUID(), url: URL, bytes: Int64, source: String) {
        self.id = id
        self.url = url
        self.bytes = bytes
        self.source = source
    }
}

enum EnqueueRejection: Equatable {
    case blacklisted, whitelisted
}

struct TrashQueue: Sendable {
    var tasks: [TrashTask] = []

    var totalBytes: Int64 {
        tasks.reduce(0) { $0 + $1.bytes }
    }

    mutating func enqueue(_ task: TrashTask, appSupport: URL, whitelist: (URL) -> Bool) -> EnqueueRejection? {
        let resolved = PathNormalizer.resolve(task.url)
        if Blacklist.blocks(resolved, appSupport: appSupport) {
            return .blacklisted
        }
        if whitelist(resolved) {
            return .whitelisted
        }
        if !tasks.contains(where: { PathNormalizer.resolve($0.url).path == resolved.path }) {
            var copy = task
            copy.url = resolved
            tasks.append(copy)
        }
        return nil
    }

    mutating func remove(id: UUID) {
        tasks.removeAll { $0.id == id }
    }

    func dryRun() -> [TrashTask] {
        tasks
    }
}

struct TrashRunner: Sendable {
    var trash: (URL) throws -> Void

    init(trash: @escaping (URL) throws -> Void = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    }) {
        self.trash = trash
    }

    func execute(_ queue: TrashQueue) -> (ok: Int, succeeded: [URL], failed: [(URL, String)]) {
        var ok = 0
        var succeeded: [URL] = []
        var failed: [(URL, String)] = []
        for task in queue.tasks {
            do {
                try trash(task.url)
                ok += 1
                succeeded.append(task.url)
            } catch {
                failed.append((task.url, error.localizedDescription))
            }
        }
        return (ok, succeeded, failed)
    }
}

struct AdministratorTrashRunner: Sendable {
    static func canHandle(_ task: TrashTask) -> Bool {
        let resolved = PathNormalizer.resolve(task.url)
        if task.source == "卸载" {
            return resolved.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame
                && resolved.deletingLastPathComponent().path == "/Applications"
                && !resolved.path.hasPrefix("/System/")
        }
        guard task.source == "卸载残留" else { return false }
        let allowedRoots = [
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/PrivilegedHelperTools",
            "/Library/Application Support"
        ]
        return allowedRoots.contains { root in
            resolved.path.hasPrefix(root + "/")
        }
    }

    static func orderedTasks(_ tasks: [TrashTask]) -> [TrashTask] {
        tasks.enumerated().sorted { left, right in
            let leftPriority = taskPriority(left.element)
            let rightPriority = taskPriority(right.element)
            return leftPriority == rightPriority ? left.offset < right.offset : leftPriority < rightPriority
        }.map(\.element)
    }

    static func retryTasks(in queue: TrashQueue, failedURLs: [URL]) -> [TrashTask] {
        let failedPaths = Set(failedURLs.map { PathNormalizer.resolve($0).path })
        return queue.tasks.filter {
            failedPaths.contains(PathNormalizer.resolve($0.url).path) && canHandle($0)
        }
    }

    func execute(_ tasks: [TrashTask]) -> (ok: Int, succeeded: [URL], failed: [(URL, String)]) {
        let fileManager = FileManager.default
        let trashDirectory = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        do {
            try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        } catch {
            return (0, [], tasks.map { ($0.url, error.localizedDescription) })
        }

        var failed = tasks.filter { !Self.canHandle($0) }.map {
            ($0.url, "管理员模式仅处理应用本体及明确选择的系统级卸载残留")
        }
        let eligibleTasks = Self.orderedTasks(tasks.filter { Self.canHandle($0) })
        guard !eligibleTasks.isEmpty else { return (0, [], failed) }

        let operations = eligibleTasks.map { task in
            (task: task, destination: uniqueDestination(for: task.url, in: trashDirectory))
        }
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            Self.appleScript,
            "\(getuid()):\(getgid())",
            "\(getuid())"
        ] + operations.flatMap { operation in
            [operation.task.url.path, operation.destination.path, Self.taskType(operation.task)]
        }
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (0, [], failed + eligibleTasks.map { ($0.url, error.localizedDescription) })
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var succeeded: [URL] = []
        for operation in operations {
            if !fileManager.fileExists(atPath: operation.task.url.path),
               fileManager.fileExists(atPath: operation.destination.path) {
                succeeded.append(operation.task.url)
            } else {
                let detail = process.terminationStatus == 0 || errorText.isEmpty
                    ? "管理员批量操作未能移到废纸篓，目标可能仍被系统服务占用"
                    : errorText
                failed.append((operation.task.url, detail))
            }
        }
        return (succeeded.count, succeeded, failed)
    }

    private static func taskPriority(_ task: TrashTask) -> Int {
        let type = taskType(task)
        if type == "launch-agent" || type == "launch-daemon" { return 0 }
        if task.source == "卸载" { return 1 }
        return 2
    }

    private static func taskType(_ task: TrashTask) -> String {
        if task.url.path.hasPrefix("/Library/LaunchDaemons/") { return "launch-daemon" }
        if task.url.path.hasPrefix("/Library/LaunchAgents/") { return "launch-agent" }
        return "file"
    }

    private func uniqueDestination(for source: URL, in trashDirectory: URL) -> URL {
        let fileManager = FileManager.default
        let initial = trashDirectory.appendingPathComponent(source.lastPathComponent)
        guard fileManager.fileExists(atPath: initial.path) else { return initial }
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        for suffix in 2...10_000 {
            let name = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            let candidate = trashDirectory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return trashDirectory.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
    }

    private static let appleScript = """
    on run argv
        set ownerSpec to item 1 of argv
        set userID to item 2 of argv
        set commandText to ""
        repeat with argumentIndex from 3 to count argv by 3
            set sourcePath to item argumentIndex of argv
            set destinationPath to item (argumentIndex + 1) of argv
            set itemType to item (argumentIndex + 2) of argv
            set actionCommand to "/bin/mv -n " & quoted form of sourcePath & " " & quoted form of destinationPath & " && /usr/sbin/chown -R " & quoted form of ownerSpec & " " & quoted form of destinationPath
            if itemType is "launch-daemon" then
                set actionCommand to "(/bin/launchctl bootout system " & quoted form of sourcePath & " >/dev/null 2>&1 || true); " & actionCommand
            else if itemType is "launch-agent" then
                set actionCommand to "(/bin/launchctl bootout gui/" & userID & " " & quoted form of sourcePath & " >/dev/null 2>&1 || true); " & actionCommand
            end if
            set wrappedCommand to "(" & actionCommand & ") >/dev/null 2>&1 || true"
            if commandText is not "" then set commandText to commandText & "; "
            set commandText to commandText & wrappedCommand
        end repeat
        do shell script commandText & "; /usr/bin/true" with administrator privileges
    end run
    """
}
