import Foundation

extension CoffeeStore {
    // MARK: - Schedule

    /// Project the schedule between two dates. Mirrors `loadScheduleData`.
    public func schedule(start: String, end: String, today: String) throws -> [ScheduleDay] {
        try Scheduler.computeSchedule(
            startDate: start,
            endDate: end,
            dailyConsumptionGrams: settings().dailyConsumptionGrams,
            beans: schedulerBeans(today: today),
            actualBrews: brews(from: start, to: end),
            today: today,
            skipDays: skipDays(from: start, to: end),
            consumptionOverrides: dayOverrides(from: start, to: end)
        )
    }

    /// All beans (including archived) so past brews can resolve names.
    private func schedulerBeans(today: String) throws -> [Scheduler.Bean] {
        let frozen = try frozenDays(today: today)
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
        return beans
    }

    private func brews(from start: String, to end: String) throws -> [Scheduler.Brew] {
        try db.query("""
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
    }

    /// Every skipped day between two dates.
    private func skipDays(from start: String, to end: String) throws -> Set<String> {
        var skipDays = Set<String>()
        for row in try db.query(
            "SELECT start_date, end_date FROM skip_days WHERE start_date <= ? AND end_date >= ?",
            [.text(end), .text(start)]
        ) {
            guard let s = row.string("start_date"), let e = row.string("end_date") else { continue }
            skipDays.formUnion(DateUtils.dateRange(max(s, start), min(e, end)))
        }
        return skipDays
    }

    /// The consumption override for each day between two dates that has one.
    /// Where overrides overlap, the newest wins.
    private func dayOverrides(from start: String, to end: String) throws -> [String: Scheduler.DayOverride] {
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
        return overrides
    }
}
