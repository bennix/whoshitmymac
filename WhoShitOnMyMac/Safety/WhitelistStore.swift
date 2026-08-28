import Foundation

final class WhitelistStore: @unchecked Sendable {
    var fileURL: URL
    private(set) var patterns: [String]

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.patterns = decoded
        } else {
            self.patterns = []
        }
    }

    func add(_ url: URL) throws {
        try addPattern(PathNormalizer.resolve(url).path)
    }

    func addPattern(_ pattern: String) throws {
        if !patterns.contains(pattern) {
            patterns.append(pattern)
        }
        try persist()
    }

    func remove(_ pattern: String) throws {
        patterns.removeAll { $0 == pattern }
        try persist()
    }

    func contains(_ url: URL) -> Bool {
        let path = PathNormalizer.resolve(url).path
        for pattern in patterns {
            if path == pattern { return true }
            if !pattern.contains("*"), isPrefix(path, of: pattern) { return true }
            if pattern.contains("*"), glob(path, pattern: pattern) { return true }
        }
        return false
    }

    private func isPrefix(_ path: String, of root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private func glob(_ value: String, pattern: String) -> Bool {
        NSPredicate(format: "SELF LIKE %@", pattern).evaluate(with: value)
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(patterns)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
