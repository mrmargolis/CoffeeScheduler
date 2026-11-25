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
          rating REAL,
          -- The rest are from version 2. bc_uuid is BeanConqueror's ID for
          -- the brew, which survives the wholesale replace on each import
          -- (the row id doesn't). logged_at is the brew's time in unix
          -- seconds, for ordering and matching cups within a day; dates
          -- are still the YYYY-MM-DD creation_date.
          bc_uuid TEXT,
          logged_at REAL,
          grinder TEXT,
          grind_setting TEXT,
          temperature_c REAL,
          water_grams REAL,
          brew_seconds INTEGER,
          method TEXT,
          water TEXT,
          profile TEXT,
          notes TEXT
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

        -- Breaks in a bag, without freezing it (BagBreak): the bag is drunk
        -- to after_grams, and the rest waits at its own place in the queue,
        -- numbered with beans.display_order. An older build doesn't know them
        -- and schedules the bag straight through.
        CREATE TABLE IF NOT EXISTS breaks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bean_id TEXT NOT NULL REFERENCES beans(id),
          after_grams REAL NOT NULL,
          display_order INTEGER
        );

        -- Feedback on a cup (CupEvaluation), from version 2. The recipe is as
        -- typed when evaluating; ratings are -2...2 against the cup wanted,
        -- NULL when not evaluated. evaluated_at is unix seconds, for order
        -- and for matching to a brew; evaluated_on is its local day.
        CREATE TABLE IF NOT EXISTS cup_evaluations (
          id TEXT PRIMARY KEY,
          bean_id TEXT NOT NULL REFERENCES beans(id),
          evaluated_at REAL NOT NULL,
          evaluated_on TEXT NOT NULL,
          grinder TEXT,
          grind_setting TEXT,
          temperature_c REAL,
          dose_grams REAL,
          water_grams REAL,
          method TEXT,
          water TEXT,
          profile TEXT,
          agitation TEXT,
          acidity INTEGER,
          sweetness INTEGER,
          intensity INTEGER,
          clarity INTEGER,
          body INTEGER,
          finish INTEGER,
          drawdown TEXT,
          flow_problem INTEGER NOT NULL DEFAULT 0,
          verdict TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_brews_bean_id ON brews(bean_id);
        CREATE INDEX IF NOT EXISTS idx_cup_evaluations_bean_id ON cup_evaluations(bean_id);
        CREATE INDEX IF NOT EXISTS idx_breaks_bean_id ON breaks(bean_id);
        CREATE INDEX IF NOT EXISTS idx_freeze_events_bean_id ON freeze_events(bean_id);
        """

    /// The schema this build reads and writes, kept in the file as SQLite's
    /// `user_version`. Raise it with any change an older build would get
    /// wrong, and add the migration below: the file is shared between
    /// devices, which may not all run the same build.
    ///
    /// 2 adds each brew's recipe and BeanConqueror ID. An older build's
    /// import would rewrite the brews without them, and lose what links an
    /// evaluation to its brew, so it must not open the file. Only one device
    /// writes the database today, so the lockout costs nothing.
    static let version = 2

    /// The brew columns version 2 adds, for a file made before it.
    static let brewRecipeColumns = [
        "bc_uuid TEXT", "logged_at REAL", "grinder TEXT", "grind_setting TEXT", "temperature_c REAL", "water_grams REAL",
        "brew_seconds INTEGER", "method TEXT", "water TEXT", "profile TEXT", "notes TEXT",
    ]

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
        // A nullable column an older build leaves alone, so it needs no new
        // version: added whenever a file doesn't have it yet
        if try !db.query("PRAGMA table_info(beans)").contains(where: { $0.string("name") == "url" }) {
            try db.execute("ALTER TABLE beans ADD COLUMN url TEXT")
        }
        try moveDatedBreaks(db)
        if found < 2 { try addBrewRecipeColumns(db) }
        if found != version {
            try db.execute("PRAGMA user_version = \(version)")
        }
    }
}

extension Schema {
    fileprivate static func addBrewRecipeColumns(_ db: SQLiteDatabase) throws {
        let columns = try Set(db.query("PRAGMA table_info(brews)").compactMap { $0.string("name") })
        for column in brewRecipeColumns where !columns.contains(String(column.prefix { $0 != " " })) {
            try db.execute("ALTER TABLE brews ADD COLUMN \(column)")
        }
    }

    /// Breaks from the build that gave each one a day to come back on, which
    /// an older build may still make: kept at their grams, and queued after
    /// the next bag, as a new break is.
    fileprivate static func moveDatedBreaks(_ db: SQLiteDatabase) throws {
        guard try !db.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'bag_breaks'").isEmpty else { return }
        try db.transaction {
            try db.execute(
                """
                INSERT INTO breaks (bean_id, after_grams) SELECT bean_id, after_grams FROM bag_breaks ORDER BY after_grams, id;
                DROP TABLE bag_breaks;
                """)
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
