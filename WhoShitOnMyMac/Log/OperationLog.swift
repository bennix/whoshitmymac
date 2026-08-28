import Foundation

struct OperationLog: Sendable {
    var fileURL: URL

    func append(_ line: String) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(stamped.utf8))
        } else {
            try Data(stamped.utf8).write(to: fileURL)
        }
    }

    func readLines() -> [String] {
        (try? String(contentsOf: fileURL, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
    }
}
