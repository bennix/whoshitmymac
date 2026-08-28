import Foundation
import SQLite3

struct SnapshotNodeFlags: OptionSet, Sendable, Equatable {
    let rawValue: Int32
    static let denied = SnapshotNodeFlags(rawValue: 1 << 0)
    static let symlink = SnapshotNodeFlags(rawValue: 1 << 1)
    static let xdev = SnapshotNodeFlags(rawValue: 1 << 2)
}

struct SnapshotNode: Equatable, Sendable {
    var parentId: Int64?
    var name: String
    var isDirectory: Bool
    var size: Int64
    var allocSize: Int64
    var mtime: Int64
    var inode: UInt64
    var flags: SnapshotNodeFlags
}

final class SnapshotStore: @unchecked Sendable {
    private var db: OpaquePointer?

    static func create(at url: URL) throws -> SnapshotStore {
        let store = SnapshotStore()
        try store.open(url)
        try store.createSchema()
        return store
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    func insert(_ node: SnapshotNode, id: Int64) throws {
        let sql = """
        INSERT INTO nodes (id, parent_id, name, is_dir, size, alloc_size, mtime, inode, flags)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw storeError("prepare insert")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        if let parent = node.parentId {
            sqlite3_bind_int64(stmt, 2, parent)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_text(stmt, 3, node.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, node.isDirectory ? 1 : 0)
        sqlite3_bind_int64(stmt, 5, node.size)
        sqlite3_bind_int64(stmt, 6, node.allocSize)
        sqlite3_bind_int64(stmt, 7, node.mtime)
        sqlite3_bind_int64(stmt, 8, Int64(bitPattern: node.inode))
        sqlite3_bind_int(stmt, 9, node.flags.rawValue)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw storeError("insert")
        }
    }

    func allNodes() throws -> [(id: Int64, node: SnapshotNode)] {
        let sql = "SELECT id, parent_id, name, is_dir, size, alloc_size, mtime, inode, flags FROM nodes ORDER BY id;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw storeError("prepare select")
        }
        defer { sqlite3_finalize(stmt) }
        var rows: [(id: Int64, node: SnapshotNode)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let parent: Int64? = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 1)
            let name = String(cString: sqlite3_column_text(stmt, 2))
            let node = SnapshotNode(
                parentId: parent,
                name: name,
                isDirectory: sqlite3_column_int(stmt, 3) != 0,
                size: sqlite3_column_int64(stmt, 4),
                allocSize: sqlite3_column_int64(stmt, 5),
                mtime: sqlite3_column_int64(stmt, 6),
                inode: UInt64(bitPattern: sqlite3_column_int64(stmt, 7)),
                flags: SnapshotNodeFlags(rawValue: sqlite3_column_int(stmt, 8))
            )
            rows.append((id, node))
        }
        return rows
    }

    func relativePath(id: Int64) throws -> String {
        var parts: [String] = []
        var current: Int64? = id
        var guardCount = 0
        while let cid = current, guardCount < 4096 {
            guard let row = try row(id: cid) else { break }
            if !row.node.name.isEmpty {
                parts.append(row.node.name)
            }
            current = row.node.parentId
            guardCount += 1
        }
        return parts.reversed().joined(separator: "/")
    }

    func pathMap() throws -> [String: SnapshotNode] {
        var map: [String: SnapshotNode] = [:]
        for row in try allNodes() {
            let path = try relativePath(id: row.id)
            map[path] = row.node
        }
        return map
    }

    private func row(id: Int64) throws -> (id: Int64, node: SnapshotNode)? {
        try allNodes().first { $0.id == id }
    }

    private func open(_ url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            throw storeError("open")
        }
    }

    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS nodes (
            id INTEGER PRIMARY KEY,
            parent_id INTEGER,
            name TEXT NOT NULL,
            is_dir INTEGER,
            size INTEGER,
            alloc_size INTEGER,
            mtime INTEGER,
            inode INTEGER,
            flags INTEGER
        );
        """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw storeError("schema")
        }
    }

    private func storeError(_ what: String) -> NSError {
        let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        return NSError(domain: "SnapshotStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(what): \(message)"])
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
