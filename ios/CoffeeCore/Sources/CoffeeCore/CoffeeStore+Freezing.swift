import Foundation

extension CoffeeStore {
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
}
