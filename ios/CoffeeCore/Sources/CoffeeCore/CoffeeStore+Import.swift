import Foundation

extension CoffeeStore {
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
    /// The one exception: a roast date the export doesn't have keeps the
    /// one already stored, so a date entered
    /// in the app for a bag BeanConqueror has none for survives a re-import.
    ///
    /// `date` is kept as the day of the last import.
    public func importExport(_ parsed: BeanConquerorParser.ParseResult, on date: String = DateUtils.today()) throws -> ImportSummary {
        try db.transaction { () throws -> ImportSummary in
            for bean in parsed.beans { try upsert(bean) }
            for event in parsed.freezeEvents { try recordFreeze(event) }
            try replaceBrews(parsed.brews)
            try db.run("INSERT OR REPLACE INTO settings (key, value) VALUES ('last_import_date', ?)", [.text(date)])

            return ImportSummary(
                beansImported: parsed.beans.count,
                brewsImported: parsed.brews.count,
                errors: parsed.errors
            )
        }
    }

    /// The day of the last import; nil before the first one. The schedule
    /// is only as current as this, since brews arrive with an import.
    public func lastImportDate() throws -> String? {
        try db.query("SELECT value FROM settings WHERE key = 'last_import_date'").first?.string("value")
    }

    private func upsert(_ bean: BeanConquerorParser.RawBean) throws {
        try db.run(
            """
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
            """,
            [
                .text(bean.id), .text(bean.name), .text(bean.roaster), SQLValue(bean.roastDate),
                .double(bean.weightGrams), SQLValue(bean.cost), SQLValue(bean.flavourProfile),
                SQLValue(bean.country), SQLValue(bean.region), SQLValue(bean.variety),
                SQLValue(bean.processing), SQLValue(bean.archived), SQLValue(bean.isFrozen),
            ])
    }

    /// Record a freeze for a currently frozen bean that has none yet.
    private func recordFreeze(_ event: BeanConquerorParser.FreezeInfo) throws {
        let existing =
            try db.query(
                "SELECT COUNT(*) as count FROM freeze_events WHERE bean_id = ? AND event_type = 'freeze'",
                [.text(event.beanID)]
            ).first?.int("count") ?? 0
        guard existing == 0 else { return }
        try db.run(
            "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, 'freeze', ?)",
            [.text(event.beanID), .text(event.frozenDate)]
        )
    }

    /// The export carries each bean's full brew history, so replace it wholesale.
    private func replaceBrews(_ brews: [BeanConquerorParser.RawBrew]) throws {
        for beanID in Set(brews.map(\.beanID)) {
            try db.run("DELETE FROM brews WHERE bean_id = ?", [.text(beanID)])
        }
        for brew in brews {
            try db.run(
                """
                INSERT INTO brews (bean_id, ground_coffee_grams, creation_date, bean_age_days, rating)
                VALUES (?, ?, ?, ?, ?)
                """,
                [
                    .text(brew.beanID), .double(brew.groundCoffeeGrams), .text(brew.creationDate),
                    SQLValue(brew.beanAgeDays), SQLValue(brew.rating),
                ])
        }
    }
}
