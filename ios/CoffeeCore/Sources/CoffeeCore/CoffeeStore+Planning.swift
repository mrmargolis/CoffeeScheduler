import Foundation

/// What the user plans around the queue: its order, skip days and one-day amounts.
extension CoffeeStore {
    // MARK: - Queue order

    /// Set the manual queue order to `ids`, numbered 1...n, as dragging a bag
    /// in the queue does. Any other bag that still has a manual
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

    /// Move a bag in the queue, as dragging it does. `ids` is the queue as it
    /// now shows: the moved bag and the bags above it are numbered in that
    /// order so they stay put, and the bags below it that were in automatic
    /// order stay automatic, still sorted by when they're ready.
    public func moveInQueue(_ ids: [String], moved: String) throws {
        guard let index = ids.firstIndex(of: moved) else { return }
        try reorderQueue(Array(ids[...index]))
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

    /// Skip every day from `start` to `end`, as the skip days form does, or
    /// with `id` move that range there. The days take `reason`. A range
    /// already on some of them keeps only its days outside the new one, so
    /// no day is in two ranges, and ranges left side by side with the same
    /// reason become one.
    public func saveSkipRange(replacing id: Int? = nil, start: String, end: String, reason: String?) throws {
        for date in [start, end] where DateUtils.dayNumber(date).map(DateUtils.isoString(dayNumber:)) != date {
            throw SkipRangeError.invalidDate(date)
        }
        guard start <= end else { throw SkipRangeError.endBeforeStart }

        let insert = "INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)"
        try db.transaction {
            if let id { try deleteSkipRange(id: id) }
            for old in try skipRanges(from: start) where old.startDate <= end {
                try deleteSkipRange(id: old.id)
                if old.startDate < start {
                    try db.run(insert, [.text(old.startDate), .text(DateUtils.addDays(start, -1)), SQLValue(old.reason)])
                }
                if old.endDate > end {
                    try db.run(insert, [.text(DateUtils.addDays(end, 1)), .text(old.endDate), SQLValue(old.reason)])
                }
            }
            try db.run(insert, [.text(start), .text(end), SQLValue(Self.cleaned(reason))])
            try joinTouchingSkipRanges()
        }
    }

    /// Make one range of any two that sit side by side with the same reason.
    private func joinTouchingSkipRanges() throws {
        var kept: SkipRange?
        for range in try skipRanges(from: "") {
            let sameReason = Self.cleaned(kept?.reason) == Self.cleaned(range.reason)
            if let last = kept, sameReason, DateUtils.addDays(last.endDate, 1) == range.startDate {
                try db.run("UPDATE skip_days SET end_date = ? WHERE id = ?", [.text(range.endDate), .int(Int64(last.id))])
                try deleteSkipRange(id: range.id)
                kept?.endDate = range.endDate
            } else {
                kept = range
            }
        }
    }

    /// A reason without the space around it, or nil when nothing is left.
    private static func cleaned(_ reason: String?) -> String? {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Skip `date`, or stop skipping it, and return whether it's now skipped.
    /// The skip_days table is kept as merged
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

    /// Set a different amount for one day, as the day options sheet does:
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
}
