import Foundation

/// Queries and writes against the coffee database. Ports the web app's
/// `bean-queries.ts`, `schedule-loader.ts`, `freeze-utils.ts`, the auto
/// freeze/thaw jobs, and the import and settings API routes.
///
/// This file has the settings and the beans; the rest is in the
/// `CoffeeStore+*.swift` extensions.
public final class CoffeeStore {
    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) throws {
        self.db = db
        try db.execute("PRAGMA foreign_keys = ON")
        try Schema.initialize(db)
    }

    /// Opens the database file at `url`. Uses a rollback journal rather than
    /// WAL so the file on disk is always complete after a commit and can be
    /// copied to iCloud Drive on its own, without -wal/-shm sidecars.
    public convenience init(url: URL) throws {
        let db = try SQLiteDatabase(path: url.path)
        try db.execute("PRAGMA journal_mode = DELETE")
        try self.init(db: db)
    }

    /// An empty in-memory database, for tests and previews.
    public static func inMemory() throws -> CoffeeStore {
        try CoffeeStore(db: SQLiteDatabase(path: ":memory:"))
    }

    // MARK: - Settings

    public func settings() throws -> ScheduleSettings {
        var values: [String: String] = [:]
        for row in try db.query("SELECT key, value FROM settings") {
            if let key = row.string("key") { values[key] = row.string("value") }
        }
        let daily = values["daily_consumption_grams"].flatMap(Double.init) ?? 0
        let rest = values["default_rest_days"].flatMap(Int.init) ?? 0
        return ScheduleSettings(
            dailyConsumptionGrams: daily != 0 ? daily : Scheduler.defaultDailyGrams,
            defaultRestDays: rest != 0 ? rest : 30
        )
    }

    public func updateSettings(_ settings: ScheduleSettings) throws {
        let sql = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
        try db.transaction {
            try db.run(sql, ["daily_consumption_grams", .text(Self.format(settings.dailyConsumptionGrams))])
            try db.run(sql, ["default_rest_days", .text(String(settings.defaultRestDays))])
        }
    }

    /// Roaster rest-day defaults, by roaster name.
    public func roasterDefaults() throws -> [RoasterDefault] {
        try db.query("SELECT roaster, rest_days FROM roaster_defaults ORDER BY roaster").compactMap { row in
            guard let roaster = row.string("roaster"), let days = row.int("rest_days") else { return nil }
            return RoasterDefault(roaster: roaster, restDays: days)
        }
    }

    /// Set a roaster's default rest days, or remove it with nil, as
    /// `PATCH /api/settings` does for each `roaster_defaults` entry.
    public func setRoasterRestDays(_ roaster: String, _ restDays: Int?) throws {
        if let restDays {
            guard restDays >= 0 else { throw BeanSettingsError.negativeRestDays }
            try db.run(
                "INSERT OR REPLACE INTO roaster_defaults (roaster, rest_days) VALUES (?, ?)",
                [.text(roaster), .int(Int64(restDays))]
            )
        } else {
            try db.run("DELETE FROM roaster_defaults WHERE roaster = ?", [.text(roaster)])
        }
    }

    /// Every roaster that appears in the beans, for picking one to set a default for.
    public func roasters() throws -> [String] {
        try db.query("SELECT DISTINCT roaster FROM beans WHERE roaster != '' ORDER BY roaster COLLATE NOCASE")
            .compactMap { $0.string("roaster") }
    }

    /// Render whole numbers without a trailing ".0", as JavaScript's String() does,
    /// so the web app reads the same text back.
    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    // MARK: - Beans

    static let beanSelect = """
          SELECT
            b.*,
            COALESCE(b.rest_days, rd.rest_days,
              CAST((SELECT value FROM settings WHERE key = 'default_rest_days') AS INTEGER)
            ) as effective_rest_days,
            COALESCE(
              (SELECT SUM(br.ground_coffee_grams) FROM brews br WHERE br.bean_id = b.id), 0
            ) as total_brewed_grams
          FROM beans b
          LEFT JOIN roaster_defaults rd ON rd.roaster = b.roaster
        """

    /// Beans in queue order: manually ordered first, then by roast date.
    public func beans(archived: Bool, today: String = DateUtils.today()) throws -> [Bean] {
        let frozen = try frozenDays(today: today)
        let frozenToDate = try frozenDays(today: today, projectToPlannedThaw: false)
        return try db.query(
            """
            \(Self.beanSelect)
            WHERE b.archived = ?
            ORDER BY
              CASE WHEN b.display_order IS NOT NULL THEN 0 ELSE 1 END,
              b.display_order,
              b.roast_date
            """, [SQLValue(archived)]
        )
        .map { Self.bean(from: $0, frozen: frozen, frozenToDate: frozenToDate) }
    }

    public func bean(id: String, today: String = DateUtils.today()) throws -> Bean? {
        guard let row = try db.query("\(Self.beanSelect) WHERE b.id = ?", [.text(id)]).first else { return nil }
        return Self.bean(
            from: row,
            frozen: try frozenDays(today: today),
            frozenToDate: try frozenDays(today: today, projectToPlannedThaw: false)
        )
    }

    /// The bag's latest brews, newest first.
    public func recentBrews(beanID: String, limit: Int = 10) throws -> [BrewRecord] {
        try db.query(
            "SELECT * FROM brews WHERE bean_id = ? ORDER BY creation_date DESC, id DESC LIMIT ?",
            [.text(beanID), .int(Int64(limit))]
        ).map {
            BrewRecord(
                creationDate: $0.string("creation_date") ?? "",
                groundCoffeeGrams: $0.double("ground_coffee_grams") ?? 0,
                rating: $0.double("rating")
            )
        }
    }

    /// The bag's freezes and thaws, oldest first.
    public func freezeEvents(beanID: String) throws -> [FreezeEvent] {
        try db.query(
            "SELECT * FROM freeze_events WHERE bean_id = ? ORDER BY event_date, id",
            [.text(beanID)]
        ).compactMap { row in
            guard let kind = row.string("event_type").flatMap(FreezeEvent.Kind.init(rawValue:)),
                let date = row.string("event_date")
            else { return nil }
            return FreezeEvent(kind: kind, date: date)
        }
    }

    private static func bean(from row: SQLRow, frozen: [String: Int], frozenToDate: [String: Int]) -> Bean {
        let id = row.string("id") ?? ""
        return Bean(
            id: id,
            name: row.string("name") ?? "",
            roaster: row.string("roaster") ?? "",
            roastDate: row.string("roast_date"),
            weightGrams: row.double("weight_grams") ?? 0,
            cost: row.double("cost"),
            flavourProfile: row.string("flavour_profile"),
            country: row.string("country"),
            region: row.string("region"),
            variety: row.string("variety"),
            processing: row.string("processing"),
            archived: row.bool("archived"),
            restDays: row.int("rest_days"),
            isFrozen: row.bool("is_frozen"),
            plannedThawDate: row.string("planned_thaw_date"),
            freezeAfterGrams: row.double("freeze_after_grams"),
            notes: row.string("notes"),
            displayOrder: row.int("display_order"),
            effectiveRestDays: row.int("effective_rest_days") ?? 0,
            totalBrewedGrams: row.double("total_brewed_grams") ?? 0,
            frozenDays: frozen[id] ?? 0,
            frozenDaysToDate: frozenToDate[id] ?? 0
        )
    }

    /// Save the user-managed settings on a bag. Mirrors the bean detail
    /// form's `PATCH /api/beans/[id]`: every field is written, and nil
    /// clears it (rest days then fall back to the roaster or global default).
    public func updateBeanSettings(id: String, _ settings: BeanSettings) throws {
        guard
            let weight = try db.query("SELECT weight_grams FROM beans WHERE id = ?", [.text(id)])
                .first?.double("weight_grams")
        else { throw BeanSettingsError.notFound }
        try settings.validate(weightGrams: weight)

        try db.run(
            """
            UPDATE beans SET rest_days = ?, roast_date = ?, planned_thaw_date = ?, freeze_after_grams = ?
            WHERE id = ?
            """,
            [
                SQLValue(settings.restDays), SQLValue(settings.roastDate),
                SQLValue(settings.plannedThawDate), SQLValue(settings.freezeAfterGrams), .text(id),
            ])
    }
}
