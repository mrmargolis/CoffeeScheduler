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

    /// Save the user-managed settings on a bag. Mirrors the bean detail
    /// form's `PATCH /api/beans/[id]`: every field is written, and nil
    /// clears it (rest days then fall back to the roaster or global default).
    public func updateBeanSettings(id: String, _ settings: BeanSettings) throws {
        guard let weight = try db.query("SELECT weight_grams FROM beans WHERE id = ?", [.text(id)])
            .first?.double("weight_grams")
        else { throw BeanSettingsError.notFound }
        try settings.validate(weightGrams: weight)

        try db.run("""
            UPDATE beans SET rest_days = ?, roast_date = ?, planned_thaw_date = ?, freeze_after_grams = ?
            WHERE id = ?
            """, [
                SQLValue(settings.restDays), SQLValue(settings.roastDate),
                SQLValue(settings.plannedThawDate), SQLValue(settings.freezeAfterGrams), .text(id),
            ])
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

    /// Freeze a bag that isn't frozen, or thaw one that is, and return its new
    /// state. Mirrors `POST /api/beans/[id]/freeze`: the planned thaw and
    /// freeze-after target are cleared either way, a freeze takes the bag out
    /// of the manual queue order, and the event is logged as of `today`.
    @discardableResult
    public func toggleFreeze(id: String, today: String) throws -> Bool {
        guard let row = try db.query("SELECT is_frozen FROM beans WHERE id = ?", [.text(id)]).first
        else { throw BeanSettingsError.notFound }
        let freezing = (row.int("is_frozen") ?? 0) == 0

        try db.transaction {
            try db.run(
                "UPDATE beans SET is_frozen = ?, planned_thaw_date = NULL, freeze_after_grams = NULL\(freezing ? ", display_order = NULL" : "") WHERE id = ?",
                [.int(freezing ? 1 : 0), .text(id)]
            )
            try db.run(
                "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, ?, ?)",
                [.text(id), .text(freezing ? "freeze" : "thaw"), .text(today)]
            )
            if freezing { try resequenceDisplayOrder() }
        }
        return freezing
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

    // MARK: - Queue order

    /// Set the manual queue order to `ids`, numbered 1...n, as dragging a bag
    /// in the web app's queue does. Any other bag that still has a manual
    /// position keeps its relative order after them, so no two bags share
    /// a number.
    public func reorderQueue(_ ids: [String]) throws {
        try db.transaction {
            let others = try db.query("SELECT id FROM beans WHERE display_order IS NOT NULL ORDER BY display_order")
                .compactMap { $0.string("id") }
                .filter { !ids.contains($0) }
            for (i, id) in (ids + others).enumerated() {
                try db.run("UPDATE beans SET display_order = ? WHERE id = ?", [.int(Int64(i + 1)), .text(id)])
            }
        }
    }

    /// Drop a bag's manual position so it's queued automatically again
    /// (after the manually ordered bags, in progress first, then by ready date).
    public func clearQueuePosition(id: String) throws {
        try db.transaction {
            try db.run("UPDATE beans SET display_order = NULL WHERE id = ?", [.text(id)])
            try resequenceDisplayOrder()
        }
    }

    /// Drop every manual position, returning the whole queue to automatic order.
    public func clearQueueOrder() throws {
        try db.run("UPDATE beans SET display_order = NULL")
    }

    // MARK: - Skip days

    /// Skip ranges that haven't ended before `from`, earliest first.
    public func skipRanges(from: String) throws -> [SkipRange] {
        try db.query("SELECT * FROM skip_days WHERE end_date >= ? ORDER BY start_date", [.text(from)])
            .compactMap { row in
                guard let id = row.int("id"), let start = row.string("start_date"), let end = row.string("end_date")
                else { return nil }
                return SkipRange(id: id, startDate: start, endDate: end, reason: row.string("reason"))
            }
    }

    public func deleteSkipRange(id: Int) throws {
        try db.run("DELETE FROM skip_days WHERE id = ?", [.int(Int64(id))])
    }

    /// Skip `date`, or stop skipping it, and return whether it's now skipped.
    /// Port of `POST /api/skip-days/toggle`, which keeps skip_days as merged
    /// ranges: skipping a day next to a range extends it (bridging two ranges
    /// when it fills the gap between them), and un-skipping a day shrinks,
    /// splits or deletes the range that holds it.
    @discardableResult
    public func toggleSkipDay(_ date: String) throws -> Bool {
        try db.transaction {
            if let range = try db.query(
                "SELECT * FROM skip_days WHERE start_date <= ? AND end_date >= ?", [.text(date), .text(date)]
            ).first, let id = range.int("id"), let start = range.string("start_date"), let end = range.string("end_date") {
                let rowID = SQLValue.int(Int64(id))
                if start == date && end == date {
                    try db.run("DELETE FROM skip_days WHERE id = ?", [rowID])
                } else if start == date {
                    try db.run("UPDATE skip_days SET start_date = ? WHERE id = ?", [.text(DateUtils.addDays(date, 1)), rowID])
                } else if end == date {
                    try db.run("UPDATE skip_days SET end_date = ? WHERE id = ?", [.text(DateUtils.addDays(date, -1)), rowID])
                } else {
                    let reason = SQLValue(range.string("reason"))
                    try db.run("DELETE FROM skip_days WHERE id = ?", [rowID])
                    try db.run(
                        "INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)",
                        [.text(start), .text(DateUtils.addDays(date, -1)), reason]
                    )
                    try db.run(
                        "INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)",
                        [.text(DateUtils.addDays(date, 1)), .text(end), reason]
                    )
                }
                return false
            }

            let prev = try db.query("SELECT id FROM skip_days WHERE end_date = ?", [.text(DateUtils.addDays(date, -1))])
                .first?.int("id")
            let next = try db.query("SELECT id, end_date FROM skip_days WHERE start_date = ?", [.text(DateUtils.addDays(date, 1))])
                .first
            if let prev, let next, let nextID = next.int("id"), let nextEnd = next.string("end_date") {
                try db.run("UPDATE skip_days SET end_date = ? WHERE id = ?", [.text(nextEnd), .int(Int64(prev))])
                try db.run("DELETE FROM skip_days WHERE id = ?", [.int(Int64(nextID))])
            } else if let prev {
                try db.run("UPDATE skip_days SET end_date = ? WHERE id = ?", [.text(date), .int(Int64(prev))])
            } else if let nextID = next?.int("id") {
                try db.run("UPDATE skip_days SET start_date = ? WHERE id = ?", [.text(date), .int(Int64(nextID))])
            } else {
                try db.run("INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, NULL)", [.text(date), .text(date)])
            }
            return true
        }
    }

    // MARK: - Consumption overrides

    /// Overrides that haven't ended before `from`, earliest first.
    /// Port of `GET /api/consumption-overrides`.
    public func consumptionOverrides(from: String) throws -> [ConsumptionOverride] {
        try db.query(
            "SELECT * FROM consumption_overrides WHERE end_date >= ? ORDER BY start_date, id", [.text(from)]
        ).compactMap { row in
            guard let id = row.int("id"), let start = row.string("start_date"), let end = row.string("end_date"),
                  let daily = row.double("daily_grams"), let dose = row.double("dose_size_grams")
            else { return nil }
            return ConsumptionOverride(id: id, startDate: start, endDate: end, dailyGrams: daily, doseSizeGrams: dose)
        }
    }

    /// Set a different amount for one day, as the web app's day options do:
    /// an override already covering the day is replaced by a one-day override.
    public func setConsumptionOverride(date: String, dailyGrams: Double, doseSizeGrams: Double) throws {
        guard dailyGrams > 0, doseSizeGrams > 0, dailyGrams.isFinite, doseSizeGrams.isFinite
        else { throw ConsumptionOverrideError.notPositive }
        try db.transaction {
            if let existing = try consumptionOverrides(from: date).first(where: { $0.covers(date) }) {
                try deleteConsumptionOverride(id: existing.id)
            }
            try db.run(
                "INSERT INTO consumption_overrides (start_date, end_date, daily_grams, dose_size_grams) VALUES (?, ?, ?, ?)",
                [.text(date), .text(date), .double(dailyGrams), .double(doseSizeGrams)]
            )
        }
    }

    public func deleteConsumptionOverride(id: Int) throws {
        try db.run("DELETE FROM consumption_overrides WHERE id = ?", [.int(Int64(id))])
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
    ///
    /// One deliberate difference from the web app's import: a roast date the
    /// export doesn't have keeps the one already stored, so a date entered
    /// in the app for a bag BeanConqueror has none for survives a re-import.
    public func importExport(_ parsed: BeanConquerorParser.ParseResult) throws -> ImportSummary {
        try db.transaction { () throws -> ImportSummary in
            for bean in parsed.beans {
                try db.run("""
                    INSERT INTO beans (id, name, roaster, roast_date, weight_grams, cost, flavour_profile, country, region, variety, processing, archived, is_frozen)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                      name = excluded.name,
                      roaster = excluded.roaster,
                      roast_date = COALESCE(excluded.roast_date, beans.roast_date),
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
