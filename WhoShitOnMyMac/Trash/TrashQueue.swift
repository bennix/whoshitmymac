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
