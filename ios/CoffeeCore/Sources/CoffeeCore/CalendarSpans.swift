/// What the month view draws: runs of consecutive days on one bag, plus skip,
/// gap and override markers. They carry no colours; the app picks those.
public struct CalendarEvent: Hashable, Sendable, Codable {
    public enum Kind: Hashable, Sendable, Codable {
        case bean(id: String, roaster: String)
        case skip
        case gap
        case override
    }

    public var kind: Kind
    public var title: String
    public var start: String
    /// Exclusive.
    public var end: String
    /// Right-aligned detail on a bag, e.g. "7 d · 315 g".
    public var meta: String?
    /// Brewed days (as opposed to projected ones).
    public var isActual: Bool = false
    /// > 0 when the bag was scheduled before it finished resting.
    public var daysEarly: Int = 0

    public var beanID: String? {
        if case .bean(let id, _) = kind { return id }
        return nil
    }
}

public enum CalendarSpans {
    public static func events(
        schedule: [ScheduleDay],
        skipRanges: [SkipRange] = [],
        overrides: [ConsumptionOverride] = []
    ) -> [CalendarEvent] {
        var skipReason: [String: String] = [:]
        for range in skipRanges {
            for date in DateUtils.dateRange(range.startDate, range.endDate) {
                skipReason[date] = range.reason.flatMap { $0.isEmpty ? nil : $0 } ?? "Skip"
            }
        }
        var overrideGrams: [String: Double] = [:]
        for o in overrides {
            for date in DateUtils.dateRange(o.startDate, o.endDate) { overrideGrams[date] = o.dailyGrams }
        }

        var builder = Builder()
        for day in schedule {
            let next = DateUtils.addDays(day.date, 1)
            func marker(_ kind: CalendarEvent.Kind, _ title: String) -> CalendarEvent {
                CalendarEvent(kind: kind, title: title, start: day.date, end: next)
            }

            if day.isSkip {
                builder.events.append(marker(.skip, skipReason[day.date] ?? "Skip"))
                builder.flushAll()
                continue
            }
            if let grams = overrideGrams[day.date] {
                builder.events.append(marker(.override, "\(gramsText(grams)) g/day"))
            }
            if day.isGap && !day.isActual {
                builder.events.append(marker(.gap, "No coffee"))
            }
            builder.add(day, until: next)
        }
        builder.flushAll()
        return builder.events
    }

    /// A run of consecutive days on one bag, still open to be extended.
    private struct Span {
        var beanID: String
        var start: String, end: String, name: String, roaster: String
        var totalGrams: Double, days: Int, isActual: Bool, daysEarly: Int

        var event: CalendarEvent {
            CalendarEvent(
                kind: .bean(id: beanID, roaster: roaster), title: name, start: start, end: end,
                meta: "\(days) d · \(Int(totalGrams.rounded())) g", isActual: isActual, daysEarly: daysEarly
            )
        }
    }

    /// Collects events, growing a span while a bag runs on from one day to the next.
    private struct Builder {
        var events: [CalendarEvent] = []
        /// Open spans, in the order they were started.
        var spans: [Span] = []

        mutating func flushAll() {
            events += spans.map(\.event)
            spans.removeAll()
        }

        /// The day's bags: one event each on a day shared between bags,
        /// otherwise one more day on the bag's span.
        mutating func add(_ day: ScheduleDay, until next: String) {
            if day.consumptions.count > 1 {
                flushAll()
                events += day.consumptions.map { c in
                    CalendarEvent(
                        kind: .bean(id: c.beanID, roaster: c.roaster), title: c.beanName, start: day.date, end: next,
                        meta: "\(Int(c.grams.rounded())) g", isActual: day.isActual, daysEarly: c.daysEarly ?? 0
                    )
                }
                return
            }
            for c in day.consumptions { extend(with: c, on: day, until: next) }
        }

        private mutating func extend(with c: Consumption, on day: ScheduleDay, until next: String) {
            let early = c.daysEarly ?? 0
            let open = spans.firstIndex { $0.beanID == c.beanID }
            if let i = open, spans[i].end == day.date, spans[i].isActual == day.isActual {
                spans[i].end = next
                spans[i].totalGrams += c.grams
                spans[i].days += 1
                spans[i].daysEarly = max(spans[i].daysEarly, early)
                return
            }

            let fresh = Span(
                beanID: c.beanID, start: day.date, end: next, name: c.beanName, roaster: c.roaster,
                totalGrams: c.grams, days: 1, isActual: day.isActual, daysEarly: early
            )
            if let i = open {
                events.append(spans[i].event)
                spans[i] = fresh
            } else {
                spans.append(fresh)
            }
        }
    }

    /// JavaScript's String() for a number: no trailing ".0".
    private static func gramsText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// One bag's run through the schedule: first and last day and grams drunk.
public struct BagRun: Hashable, Sendable {
    public var beanID: String
    public var name: String
    public var roaster: String
    public var start: String
    /// Inclusive.
    public var end: String
    public var grams: Double
}

extension Scheduler {
    /// Each bag's run, in the order the bags are first drunk. Port of `collectBagRuns`.
    public static func bagRuns(_ schedule: [ScheduleDay]) -> [BagRun] {
        var order: [String] = []
        var runs: [String: BagRun] = [:]
        for day in schedule {
            for c in day.consumptions {
                if runs[c.beanID] != nil {
                    runs[c.beanID]!.end = day.date
                    runs[c.beanID]!.grams += c.grams
                } else {
                    order.append(c.beanID)
                    runs[c.beanID] = BagRun(
                        beanID: c.beanID, name: c.beanName, roaster: c.roaster,
                        start: day.date, end: day.date, grams: c.grams
                    )
                }
            }
        }
        return order.compactMap { runs[$0] }
    }

    /// Collision-free roaster colours for the bags in `schedule`, assigned in
    /// the order they're first drunk.
    public static func roasterColors(_ schedule: [ScheduleDay]) -> [String: RoasterColor] {
        RoasterColor.assign(bagRuns(schedule).map(\.roaster))
    }
}
