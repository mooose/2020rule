import Foundation
import SQLite3

final class StatsStore {
    private let appName = "2020Rule"
    private let dbFileName = "stats.db"
    private let queue = DispatchQueue(label: "com.siegfried.2020rule.stats")
    private var db: OpaquePointer?

    init() throws {
        let dbPath = try Self.databasePath(appName: appName, dbFileName: dbFileName)
        let dbDir = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        if sqlite3_open(dbPath, &handle) != SQLITE_OK {
            defer { if handle != nil { sqlite3_close(handle) } }
            throw Self.makeSQLError(db: handle, fallback: "failed to open database")
        }

        db = handle
        try execute(sql: Self.schema)
    }

    deinit {
        try? close()
    }

    func close() throws {
        try queue.sync {
            guard let db else { return }
            if sqlite3_close(db) != SQLITE_OK {
                throw Self.makeSQLError(db: db, fallback: "failed to close database")
            }
            self.db = nil
        }
    }

    func startSession() throws -> Int64 {
        try queue.sync {
            let sql = "INSERT INTO sessions (started_at) VALUES (?);"
            let now = Date().timeIntervalSince1970
            try run(sql: sql, bind: { stmt in
                sqlite3_bind_double(stmt, 1, now)
            })
            return sqlite3_last_insert_rowid(requiredDB)
        }
    }

    func endSession(sessionID: Int64, pausedDuration: TimeInterval) throws {
        try queue.sync {
            let sql = "UPDATE sessions SET ended_at = ?, paused_duration_seconds = ? WHERE id = ?;"
            let now = Date().timeIntervalSince1970
            try run(sql: sql, bind: { stmt in
                sqlite3_bind_double(stmt, 1, now)
                sqlite3_bind_int(stmt, 2, Int32(pausedDuration))
                sqlite3_bind_int64(stmt, 3, sessionID)
            })
        }
    }

    func recordBreakStart() throws -> Int64 {
        try queue.sync {
            let sql = "INSERT INTO breaks (started_at) VALUES (?);"
            let now = Date().timeIntervalSince1970
            try run(sql: sql, bind: { stmt in
                sqlite3_bind_double(stmt, 1, now)
            })
            return sqlite3_last_insert_rowid(requiredDB)
        }
    }

    func recordBreakComplete(breakID: Int64, duration: TimeInterval) throws {
        try queue.sync {
            let now = Date()
            let sql = "UPDATE breaks SET completed_at = ?, was_completed = 1, duration_seconds = ? WHERE id = ?;"
            try run(sql: sql, bind: { stmt in
                sqlite3_bind_double(stmt, 1, now.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 2, Int32(duration.rounded()))
                sqlite3_bind_int64(stmt, 3, breakID)
            })
            try updateDailyStats(for: now)
        }
    }

    func recordBreakSkipped(breakID: Int64) throws {
        try queue.sync {
            let now = Date()
            let sql = "UPDATE breaks SET completed_at = ?, was_skipped = 1 WHERE id = ?;"
            try run(sql: sql, bind: { stmt in
                sqlite3_bind_double(stmt, 1, now.timeIntervalSince1970)
                sqlite3_bind_int64(stmt, 2, breakID)
            })
            try updateDailyStats(for: now)
        }
    }

    func getComplianceReport(period: String) throws -> ComplianceReport {
        try queue.sync {
            let now = Date()
            let startDate: Date

            switch period {
            case "today":
                startDate = Calendar.current.startOfDay(for: now)
            case "week":
                startDate = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            case "month":
                startDate = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
            default:
                throw NSError(domain: "StatsStore", code: 100, userInfo: [NSLocalizedDescriptionKey: "invalid period: \(period)"])
            }

            let sql = """
            SELECT
                COUNT(*) as total,
                COALESCE(SUM(CASE WHEN was_completed = 1 THEN 1 ELSE 0 END), 0) as completed,
                COALESCE(SUM(CASE WHEN was_skipped = 1 THEN 1 ELSE 0 END), 0) as skipped
            FROM breaks
            WHERE started_at >= ?;
            """

            var total = 0
            var completed = 0
            var skipped = 0

            try querySingle(sql: sql, bind: { stmt in
                sqlite3_bind_double(stmt, 1, startDate.timeIntervalSince1970)
            }, row: { stmt in
                total = Int(sqlite3_column_int(stmt, 0))
                completed = Int(sqlite3_column_int(stmt, 1))
                skipped = Int(sqlite3_column_int(stmt, 2))
            })

            let complianceRate = calculateComplianceRate(completed: completed, total: total)
            let rawDays = Int(now.timeIntervalSince(startDate) / 86_400)
            let days = max(rawDays, 1)
            let averagePerDay = Double(completed) / Double(days)

            return ComplianceReport(
                period: period,
                totalBreaks: total,
                completedBreaks: completed,
                skippedBreaks: skipped,
                complianceRate: complianceRate,
                averagePerDay: averagePerDay
            )
        }
    }

    private func updateDailyStats(for date: Date) throws {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        let dayKey = Self.dayKey(from: startOfDay)

        var required = 0
        var completed = 0
        var skipped = 0

        let selectSQL = """
        SELECT
            COUNT(*) as required,
            COALESCE(SUM(CASE WHEN was_completed = 1 THEN 1 ELSE 0 END), 0) as completed,
            COALESCE(SUM(CASE WHEN was_skipped = 1 THEN 1 ELSE 0 END), 0) as skipped
        FROM breaks
        WHERE started_at >= ? AND started_at < ?;
        """

        try querySingle(sql: selectSQL, bind: { stmt in
            sqlite3_bind_double(stmt, 1, startOfDay.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, endOfDay.timeIntervalSince1970)
        }, row: { stmt in
            required = Int(sqlite3_column_int(stmt, 0))
            completed = Int(sqlite3_column_int(stmt, 1))
            skipped = Int(sqlite3_column_int(stmt, 2))
        })

        let complianceRate = calculateComplianceRate(completed: completed, total: required)

        let upsertSQL = """
        INSERT INTO daily_stats (date, breaks_required, breaks_completed, breaks_skipped, compliance_rate)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(date) DO UPDATE SET
            breaks_required = excluded.breaks_required,
            breaks_completed = excluded.breaks_completed,
            breaks_skipped = excluded.breaks_skipped,
            compliance_rate = excluded.compliance_rate;
        """

        try run(sql: upsertSQL, bind: { stmt in
            sqlite3_bind_text(stmt, 1, dayKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(required))
            sqlite3_bind_int(stmt, 3, Int32(completed))
            sqlite3_bind_int(stmt, 4, Int32(skipped))
            sqlite3_bind_double(stmt, 5, complianceRate)
        })
    }

    private func execute(sql: String) throws {
        try queue.sync {
            var errorMessage: UnsafeMutablePointer<Int8>?
            if sqlite3_exec(requiredDB, sql, nil, nil, &errorMessage) != SQLITE_OK {
                let message = errorMessage.map { String(cString: $0) } ?? "unknown sqlite error"
                sqlite3_free(errorMessage)
                throw NSError(domain: "StatsStore", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
    }

    private func run(sql: String, bind: (OpaquePointer) -> Void = { _ in }) throws {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(requiredDB, sql, -1, &statement, nil) != SQLITE_OK {
            throw Self.makeSQLError(db: requiredDB, fallback: "failed to prepare statement")
        }

        guard let stmt = statement else {
            throw NSError(domain: "StatsStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "statement preparation failed"])
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw Self.makeSQLError(db: requiredDB, fallback: "failed to execute statement")
        }
    }

    private func querySingle(
        sql: String,
        bind: (OpaquePointer) -> Void = { _ in },
        row: (OpaquePointer) -> Void
    ) throws {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(requiredDB, sql, -1, &statement, nil) != SQLITE_OK {
            throw Self.makeSQLError(db: requiredDB, fallback: "failed to prepare query")
        }

        guard let stmt = statement else {
            throw NSError(domain: "StatsStore", code: 4, userInfo: [NSLocalizedDescriptionKey: "query preparation failed"])
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt)

        let stepResult = sqlite3_step(stmt)
        if stepResult == SQLITE_ROW {
            row(stmt)
            return
        }

        if stepResult == SQLITE_DONE {
            return
        }

        throw Self.makeSQLError(db: requiredDB, fallback: "query execution failed")
    }

    private var requiredDB: OpaquePointer {
        guard let db else {
            fatalError("database not initialized")
        }
        return db
    }

    private static func databasePath(appName: String, dbFileName: String) throws -> String {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "StatsStore", code: 5, userInfo: [NSLocalizedDescriptionKey: "No application support directory found"])
        }
        return appSupport.appendingPathComponent(appName, isDirectory: true).appendingPathComponent(dbFileName).path
    }

    private static func makeSQLError(db: OpaquePointer?, fallback: String) -> NSError {
        if let db, let cString = sqlite3_errmsg(db) {
            return NSError(domain: "StatsStore", code: 6, userInfo: [NSLocalizedDescriptionKey: String(cString: cString)])
        }
        return NSError(domain: "StatsStore", code: 6, userInfo: [NSLocalizedDescriptionKey: fallback])
    }

    private static func dayKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static let schema = """
    CREATE TABLE IF NOT EXISTS breaks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at REAL NOT NULL,
        completed_at REAL,
        was_completed INTEGER DEFAULT 0,
        was_skipped INTEGER DEFAULT 0,
        duration_seconds INTEGER
    );

    CREATE TABLE IF NOT EXISTS daily_stats (
        date TEXT PRIMARY KEY,
        breaks_required INTEGER DEFAULT 0,
        breaks_completed INTEGER DEFAULT 0,
        breaks_skipped INTEGER DEFAULT 0,
        total_work_minutes INTEGER DEFAULT 0,
        compliance_rate REAL
    );

    CREATE TABLE IF NOT EXISTS sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at REAL NOT NULL,
        ended_at REAL,
        paused_duration_seconds INTEGER DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_breaks_started_at ON breaks(started_at);
    CREATE INDEX IF NOT EXISTS idx_daily_stats_date ON daily_stats(date);
    CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON sessions(started_at);
    """
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
