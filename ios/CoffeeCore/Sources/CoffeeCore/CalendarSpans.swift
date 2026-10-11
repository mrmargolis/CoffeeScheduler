/// What the month view draws: runs of consecutive days on one bag, plus skip,
/// gap and override markers. Port of `buildCalendarEvents` in
/// `src/lib/calendar-utils.ts` (without the web colours, which the app picks).
public struct CalendarEvent: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case bean(id: String, roaster: String)
        case skip
        case gap
        case override
    }

    public var kind: Kind
    public var title: String
    public var start: String
    /// Exclusive, as in the web calendar.
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

        struct Span {
            var start: String, end: String, name: String, roaster: String
            var totalGrams: Double, days: Int, isActual: Bool, daysEarly: Int
        }
        var events: [CalendarEvent] = []
        // Open spans, in the order they were started (the web Map's order)
        var spans: [(id: String, span: Span)] = []

        func spanEvent(_ id: String, _ s: Span) -> CalendarEvent {
            CalendarEvent(
                kind: .bean(id: id, roaster: s.roaster), title: s.name, start: s.start, end: s.end,
                meta: "\(s.days) d · \(Int(s.totalGrams.rounded())) g", isActual: s.isActual, daysEarly: s.daysEarly
            )
        }
        func flushAll() {
            events += spans.map { spanEvent($0.id, $0.span) }
            spans.removeAll()
        }

        for day in schedule {
            let next = DateUtils.addDays(day.date, 1)
            if day.isSkip {
                events.append(CalendarEvent(kind: .skip, title: skipReason[day.date] ?? "Skip", start: day.date, end: next))
                flushAll()
                continue
            }
            if let grams = overrideGrams[day.date] {
                events.append(CalendarEvent(kind: .override, title: "\(gramsText(grams)) g/day", start: day.date, end: next))
            }
            if day.isGap && !day.isActual {
                events.append(CalendarEvent(kind: .gap, title: "No coffee", start: day.date, end: next))
            }

            if day.consumptions.count > 1 {
                flushAll()
                for c in day.consumptions {
                    events.append(CalendarEvent(
                        kind: .bean(id: c.beanID, roaster: c.roaster), title: c.beanName, start: day.date, end: next,
                        meta: "\(Int(c.grams.rounded())) g", isActual: day.isActual, daysEarly: c.daysEarly ?? 0
                    ))
                }
                continue
            }
            for c in day.consumptions {
                let early = c.daysEarly ?? 0
                if let i = spans.firstIndex(where: { $0.id == c.beanID }),
                   spans[i].span.end == day.date, spans[i].span.isActual == day.isActual {
                    spans[i].span.end = next
                    spans[i].span.totalGrams += c.grams
                    spans[i].span.days += 1
                    spans[i].span.daysEarly = max(spans[i].span.daysEarly, early)
                } else {
                    let fresh = Span(
                        start: day.date, end: next, name: c.beanName, roaster: c.roaster,
                        totalGrams: c.grams, days: 1, isActual: day.isActual, daysEarly: early
                    )
                    if let i = spans.firstIndex(where: { $0.id == c.beanID }) {
                        events.append(spanEvent(c.beanID, spans[i].span))
                        spans[i].span = fresh
                    } else {
                        spans.append((c.beanID, fresh))
                    }
                }
            }
        }
        flushAll()
        return events
    }

    /// JavaScript's String() for a number: no trailing ".0".
    private static func gramsText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// One bag's run through the schedule: first and last day and grams drunk.
/// Port of `BagRun` in `src/lib/schedule-html.ts`.
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
    /// the order they're first drunk, as the published page does.
    public static func roasterColors(_ schedule: [ScheduleDay]) -> [String: RoasterColor] {
        RoasterColor.assign(bagRuns(schedule).map(\.roaster))
    }
}
