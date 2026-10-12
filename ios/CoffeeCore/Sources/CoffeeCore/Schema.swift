import Foundation

/// The database's tables and migrations. The schema began in a web app this
/// one replaced, so a `coffee.db` from it still opens.
enum Schema {
    static let sql = """
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );

        INSERT OR IGNORE INTO settings (key, value) VALUES ('daily_consumption_grams', '45');
        INSERT OR IGNORE INTO settings (key, value) VALUES ('default_rest_days', '30');

        CREATE TABLE IF NOT EXISTS beans (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          roaster TEXT NOT NULL DEFAULT '',
          roast_date TEXT,
          weight_grams REAL NOT NULL DEFAULT 0,
          cost REAL,
          flavour_profile TEXT,
          country TEXT,
          region TEXT,
          variety TEXT,
          processing TEXT,
          archived INTEGER NOT NULL DEFAULT 0,
          rest_days INTEGER,
          is_frozen INTEGER NOT NULL DEFAULT 0,
          notes TEXT,
          display_order INTEGER
        );

        CREATE TABLE IF NOT EXISTS brews (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bean_id TEXT NOT NULL REFERENCES beans(id),
          ground_coffee_grams REAL NOT NULL DEFAULT 0,
          creation_date TEXT NOT NULL,
          bean_age_days INTEGER,
          rating REAL
        );

        CREATE TABLE IF NOT EXISTS roaster_defaults (
          roaster TEXT PRIMARY KEY,
          rest_days INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS freeze_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bean_id TEXT NOT NULL REFERENCES beans(id),
          event_type TEXT NOT NULL CHECK(event_type IN ('freeze', 'thaw')),
          event_date TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS skip_days (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          start_date TEXT NOT NULL,
          end_date TEXT NOT NULL,
          reason TEXT
        );

        CREATE TABLE IF NOT EXISTS consumption_overrides (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          start_date TEXT NOT NULL,
          end_date TEXT NOT NULL,
          daily_grams REAL NOT NULL,
          dose_size_grams REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_brews_bean_id ON brews(bean_id);
        CREATE INDEX IF NOT EXISTS idx_freeze_events_bean_id ON freeze_events(bean_id);
        """

    /// The schema this build reads and writes, kept in the file as SQLite's
    /// `user_version`. Raise it with any change an older build would get
    /// wrong, and add the migration below: the file is shared between
    /// devices, which may not all run the same build.
    static let version = 1

    static func initialize(_ db: SQLiteDatabase) throws {
        // A file from the web app, or one not made yet, is at 0
        let found = try db.query("PRAGMA user_version").first?.int("user_version") ?? 0
        guard found <= version else { throw SchemaError.newerThanApp(found: found) }

        try db.execute(sql)
        if found < 1 {
            let columns = try Set(db.query("PRAGMA table_info(beans)").compactMap { $0.string("name") })
            if !columns.contains("planned_thaw_date") {
                try db.execute("ALTER TABLE beans ADD COLUMN planned_thaw_date TEXT")
            }
            if !columns.contains("freeze_after_grams") {
                try db.execute("ALTER TABLE beans ADD COLUMN freeze_after_grams REAL")
            }
        }
        if found != version {
            try db.execute("PRAGMA user_version = \(version)")
        }
    }
}

public enum SchemaError: LocalizedError, Equatable {
    /// The file was last written by a build with a later schema.
    case newerThanApp(found: Int)

    public var errorDescription: String? {
        switch self {
        case .newerThanApp:
            "This database was saved by a newer version of Coffee Scheduler. Update the app on this device to open it."
        }
    }
}
