import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

public enum SQLValue: Equatable, Sendable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
}

extension SQLValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .text(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(nilLiteral: ()) { self = .null }

    public init(_ value: String?) { self = value.map { .text($0) } ?? .null }
    public init(_ value: Double?) { self = value.map { .double($0) } ?? .null }
    public init(_ value: Int?) { self = value.map { .int(Int64($0)) } ?? .null }
    public init(_ value: Bool) { self = .int(value ? 1 : 0) }
}

public struct SQLRow: Sendable {
    let values: [String: SQLValue]

    public subscript(_ column: String) -> SQLValue { values[column] ?? .null }

    public func string(_ column: String) -> String? {
        switch self[column] {
        case .text(let s): s
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .null: nil
        }
    }

    public func double(_ column: String) -> Double? {
        switch self[column] {
        case .int(let i): Double(i)
        case .double(let d): d
        case .text(let s): Double(s)
        case .null: nil
        }
    }

    public func int(_ column: String) -> Int? {
        switch self[column] {
        case .int(let i): Int(i)
        case .double(let d): Int(d)
        case .text(let s): Int(s)
        case .null: nil
        }
    }

    public func bool(_ column: String) -> Bool { (int(column) ?? 0) != 0 }
}

public struct SQLiteError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// A thin wrapper over the SQLite C API: enough for the store, nothing more.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    /// Opens (creating if needed) the database at `path`. Use ":memory:" for tests.
    public init(path: String) throws {
        if sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw SQLiteError(message: "Could not open database: \(message)")
        }
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Run one or more statements with no parameters or results.
    public func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw SQLiteError(message: message)
        }
    }

    public func run(_ sql: String, _ params: [SQLValue] = []) throws {
        _ = try query(sql, params)
    }

    @discardableResult
    public func query(_ sql: String, _ params: [SQLValue] = []) throws -> [SQLRow] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError(message: "\(lastError) in: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }

        try bind(params, to: stmt)

        var rows: [SQLRow] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw SQLiteError(message: "\(lastError) in: \(sql)") }
            rows.append(Self.currentRow(of: stmt))
        }
        return rows
    }

    private func bind(_ params: [SQLValue], to stmt: OpaquePointer?) throws {
        for (i, value) in params.enumerated() {
            let index = Int32(i + 1)
            let rc: Int32 = switch value {
            case .null: sqlite3_bind_null(stmt, index)
            case .int(let v): sqlite3_bind_int64(stmt, index, v)
            case .double(let v): sqlite3_bind_double(stmt, index, v)
            case .text(let v): sqlite3_bind_text(stmt, index, v, -1, Self.transient)
            }
            guard rc == SQLITE_OK else { throw SQLiteError(message: lastError) }
        }
    }

    /// The row a statement has just stepped to.
    private static func currentRow(of stmt: OpaquePointer?) -> SQLRow {
        var values: [String: SQLValue] = [:]
        for col in 0..<sqlite3_column_count(stmt) {
            let name = String(cString: sqlite3_column_name(stmt, col))
            values[name] = switch sqlite3_column_type(stmt, col) {
            case SQLITE_INTEGER: .int(sqlite3_column_int64(stmt, col))
            case SQLITE_FLOAT: .double(sqlite3_column_double(stmt, col))
            case SQLITE_TEXT: .text(String(cString: sqlite3_column_text(stmt, col)))
            default: .null
            }
        }
        return SQLRow(values: values)
    }

    /// Runs `body` in a transaction, rolling back if it throws.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private var lastError: String { String(cString: sqlite3_errmsg(handle)) }

    // SQLITE_TRANSIENT: tells SQLite to copy bound strings before returning.
    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}
