import Foundation

/// Queries and writes against the coffee database. Ports the web app's
/// `bean-queries.ts`, `schedule-loader.ts`, `freeze-utils.ts`, the auto
/// freeze/thaw jobs, and the import and settings API routes.
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

    /// Render whole numbers without a trailing ".0", as JavaScript's String() does,
    /// so the web app reads the same text back.
    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    // MARK: - Beans

    private static let beanSelect = """
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
        return try db.query("""
            \(Self.beanSelect)
            WHERE b.archived = ?
            ORDER BY
              CASE WHEN b.display_order IS NOT NULL THEN 0 ELSE 1 END,
              b.display_order,
              b.roast_date
            """, [SQLValue(archived)])
            .map { Self.bean(from: $0, frozen: frozen, frozenToDate: frozenToDate) }
    }

    public func allBeans(today: String = DateUtils.today()) throws -> [Bean] {
        let frozen = try frozenDays(today: today)
        let frozenToDate = try frozenDays(today: today, projectToPlannedThaw: false)
        return try db.query(Self.beanSelect)
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

    // MARK: - Freezing

    /// Total days each bean has spent frozen, from freeze_events. Balanced
    /// freeze→thaw pairs count (thaw - freeze); a still-open freeze counts up
    /// to the bean's planned thaw date if set, otherwise up to `today`. That
    /// projection suits ready dates and the schedule; pass
    /// `projectToPlannedThaw: false` to stop an open freeze at today instead.
    public func frozenDays(today: String, projectToPlannedThaw: Bool = true) throws -> [String: Int] {
        var frozen: [String: Int] = [:]
        var activeStart: [String: String] = [:]

        for event in try db.query("SELECT bean_id, event_type, event_date FROM freeze_events ORDER BY event_date") {
            guard let beanID = event.string("bean_id"), let date = event.string("event_date") else { continue }
            if event.string("event_type") == "freeze" {
                activeStart[beanID] = date
            } else if let start = activeStart.removeValue(forKey: beanID) {
                frozen[beanID, default: 0] += DateUtils.daysBetween(start, date)
            }
        }

        for (beanID, start) in activeStart {
            var thaw: String?
            if projectToPlannedThaw {
                thaw = try db.query("SELECT planned_thaw_date FROM beans WHERE id = ?", [.text(beanID)])
                    .first?.string("planned_thaw_date")
            }
            frozen[beanID, default: 0] += DateUtils.daysBetween(start, thaw ?? today)
        }
        return frozen
    }

    /// Thaw beans whose planned thaw date has arrived.
    public func autoThaw(today: String) throws {
        let due = try db.query(
            "SELECT id FROM beans WHERE is_frozen = 1 AND planned_thaw_date IS NOT NULL AND planned_thaw_date <= ?",
            [.text(today)]
        ).compactMap { $0.string("id") }
        guard !due.isEmpty else { return }

        try db.transaction {
            for id in due {
                try db.run("UPDATE beans SET is_frozen = 0, planned_thaw_date = NULL WHERE id = ?", [.text(id)])
                try db.run(
                    "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, 'thaw', ?)",
                    [.text(id), .text(today)]
                )
            }
        }
    }

    /// Freeze beans whose brewed grams have reached their freeze-after target.
    public func autoFreeze(today: String) throws {
        let due = try db.query("""
            SELECT b.id FROM beans b
            WHERE b.is_frozen = 0
              AND b.freeze_after_grams IS NOT NULL
              AND (SELECT COALESCE(SUM(br.ground_coffee_grams), 0) FROM brews br WHERE br.bean_id = b.id) + 12 >= b.freeze_after_grams
            """).compactMap { $0.string("id") }
        guard !due.isEmpty else { return }

        try db.transaction {
            for id in due {
                try db.run(
                    "UPDATE beans SET is_frozen = 1, freeze_after_grams = NULL, display_order = NULL WHERE id = ?",
                    [.text(id)]
                )
                try db.run(
                    "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, 'freeze', ?)",
                    [.text(id), .text(today)]
                )
            }
            try resequenceDisplayOrder()
        }
    }

    /// Renumber manually ordered beans 1, 2, 3, ... with no gaps.
    func resequenceDisplayOrder() throws {
        let ids = try db.query("SELECT id FROM beans WHERE display_order IS NOT NULL ORDER BY display_order")
            .compactMap { $0.string("id") }
        for (i, id) in ids.enumerated() {
            try db.run("UPDATE beans SET display_order = ? WHERE id = ?", [.int(Int64(i + 1)), .text(id)])
        }
    }

    // MARK: - Import

    public struct ImportSummary: Sendable {
        public var beansImported: Int
        public var brewsImported: Int
        public var errors: [String]
    }

    /// Merge a parsed BeanConqueror export into the database. BeanConqueror
    /// owns bean metadata and brews; user-managed fields (rest days, queue
    /// order, freeze plans, notes) are left alone.
    public func importExport(_ parsed: BeanConquerorParser.ParseResult) throws -> ImportSummary {
        try db.transaction { () throws -> ImportSummary in
            for bean in parsed.beans {
                try db.run("""
                    INSERT INTO beans (id, name, roaster, roast_date, weight_grams, cost, flavour_profile, country, region, variety, processing, archived, is_frozen)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                      name = excluded.name,
                      roaster = excluded.roaster,
                      roast_date = excluded.roast_date,
                      weight_grams = excluded.weight_grams,
                      cost = excluded.cost,
                      flavour_profile = excluded.flavour_profile,
                      country = excluded.country,
                      region = excluded.region,
                      variety = excluded.variety,
                      processing = excluded.processing,
                      archived = excluded.archived,
                      is_frozen = MAX(beans.is_frozen, excluded.is_frozen)
                    """, [
                        .text(bean.id), .text(bean.name), .text(bean.roaster), SQLValue(bean.roastDate),
                        .double(bean.weightGrams), SQLValue(bean.cost), SQLValue(bean.flavourProfile),
                        SQLValue(bean.country), SQLValue(bean.region), SQLValue(bean.variety),
                        SQLValue(bean.processing), SQLValue(bean.archived), SQLValue(bean.isFrozen),
                    ])
            }

            // Record a freeze for currently frozen beans that have none yet
            for event in parsed.freezeEvents {
                let existing = try db.query(
                    "SELECT COUNT(*) as count FROM freeze_events WHERE bean_id = ? AND event_type = 'freeze'",
                    [.text(event.beanID)]
                ).first?.int("count") ?? 0
                if existing == 0 {
                    try db.run(
                        "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, 'freeze', ?)",
                        [.text(event.beanID), .text(event.frozenDate)]
                    )
                }
            }

            // The export carries each bean's full brew history, so replace it wholesale
            for beanID in Set(parsed.brews.map(\.beanID)) {
                try db.run("DELETE FROM brews WHERE bean_id = ?", [.text(beanID)])
            }
            for brew in parsed.brews {
                try db.run("""
                    INSERT INTO brews (bean_id, ground_coffee_grams, creation_date, bean_age_days, rating)
                    VALUES (?, ?, ?, ?, ?)
                    """, [
                        .text(brew.beanID), .double(brew.groundCoffeeGrams), .text(brew.creationDate),
                        SQLValue(brew.beanAgeDays), SQLValue(brew.rating),
                    ])
            }

            return ImportSummary(
                beansImported: parsed.beans.count,
                brewsImported: parsed.brews.count,
                errors: parsed.errors
            )
        }
    }

    // MARK: - Schedule

    /// Project the schedule between two dates. Mirrors `loadScheduleData`.
    public func schedule(start: String, end: String, today: String) throws -> [ScheduleDay] {
        let settings = try self.settings()
        let frozen = try frozenDays(today: today)

        // All beans (including archived) so past brews can resolve names
        var beans = try db.query(Self.beanSelect).map { row -> Scheduler.Bean in
            let id = row.string("id") ?? ""
            let weight = row.double("weight_grams") ?? 0
            return Scheduler.Bean(
                id: id,
                name: row.string("name") ?? "",
                roaster: row.string("roaster") ?? "",
                roastDate: row.string("roast_date"),
                weightGrams: weight,
                remainingGrams: row.bool("archived") ? 0 : weight - (row.double("total_brewed_grams") ?? 0),
                effectiveRestDays: row.int("effective_rest_days") ?? 0,
                isFrozen: row.bool("is_frozen"),
                plannedThawDate: row.string("planned_thaw_date").flatMap { $0.isEmpty ? nil : $0 },
                freezeAfterGrams: row.double("freeze_after_grams"),
                displayOrder: row.int("display_order"),
                frozenDays: frozen[id] ?? 0
            )
        }

        // Future brews are projected day by day, so add them back to remaining
        let futureTotals = try db.query("""
            SELECT bean_id, SUM(ground_coffee_grams) as total_grams
            FROM brews WHERE creation_date > ?
            GROUP BY bean_id
            """, [.text(today)])
        for row in futureTotals {
            if let i = beans.firstIndex(where: { $0.id == row.string("bean_id") }) {
                beans[i].remainingGrams += row.double("total_grams") ?? 0
            }
        }

        let brews = try db.query("""
            SELECT bean_id, creation_date, ground_coffee_grams
            FROM brews
            WHERE creation_date >= ? AND creation_date <= ?
            ORDER BY creation_date
            """, [.text(start), .text(end)]
        ).map {
            Scheduler.Brew(
                beanID: $0.string("bean_id") ?? "",
                creationDate: $0.string("creation_date") ?? "",
                groundCoffeeGrams: $0.double("ground_coffee_grams") ?? 0
            )
        }

        var skipDays = Set<String>()
        for row in try db.query(
            "SELECT start_date, end_date FROM skip_days WHERE start_date <= ? AND end_date >= ?",
            [.text(end), .text(start)]
        ) {
            guard let s = row.string("start_date"), let e = row.string("end_date") else { continue }
            skipDays.formUnion(DateUtils.dateRange(max(s, start), min(e, end)))
        }

        var overrides: [String: Scheduler.DayOverride] = [:]
        for row in try db.query(
            "SELECT * FROM consumption_overrides WHERE start_date <= ? AND end_date >= ? ORDER BY id",
            [.text(end), .text(start)]
        ) {
            guard let s = row.string("start_date"), let e = row.string("end_date") else { continue }
            let override = Scheduler.DayOverride(
                dailyGrams: row.double("daily_grams") ?? 0,
                doseSize: row.double("dose_size_grams") ?? Scheduler.doseSizeGrams
            )
            for date in DateUtils.dateRange(max(s, start), min(e, end)) { overrides[date] = override }
        }

        return Scheduler.computeSchedule(
            startDate: start,
            endDate: end,
            dailyConsumptionGrams: settings.dailyConsumptionGrams,
            beans: beans,
            actualBrews: brews,
            today: today,
            skipDays: skipDays,
            consumptionOverrides: overrides
        )
    }
}
