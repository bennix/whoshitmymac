import Foundation
import SwiftData

@Model
final class SnapshotRecord {
    var id: UUID
    var createdAt: Date
    var rootPath: String
    var note: String
    var fileCount: Int
    var totalBytes: Int64
    var deniedCount: Int
    var elapsed: Double
    var incomplete: Bool
    var sqliteFileName: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        rootPath: String,
        note: String = "",
        fileCount: Int = 0,
        totalBytes: Int64 = 0,
        deniedCount: Int = 0,
        elapsed: Double = 0,
        incomplete: Bool = false,
        sqliteFileName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rootPath = rootPath
        self.note = note
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.deniedCount = deniedCount
        self.elapsed = elapsed
        self.incomplete = incomplete
        self.sqliteFileName = sqliteFileName ?? "\(id.uuidString).sqlite"
    }
}
