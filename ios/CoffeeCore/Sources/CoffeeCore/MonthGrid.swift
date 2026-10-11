import Foundation

/// How a month of calendar events is laid out in weeks: shared by the app's
/// month view and the widget, which draw the same grid.
public enum MonthGrid {
    /// One event's part of one week.
    public struct Segment: Hashable, Sendable {
        public let event: CalendarEvent
        /// 0 = Monday ... 6 = Sunday.
        public let startColumn: Int
        /// Inclusive.
        public let endColumn: Int
        /// Which row of bars it sits in, from 0, when several overlap.
        public let lane: Int
        /// The span begins in this week (as opposed to continuing from the last).
        public let isStart: Bool
        /// The span ends in this week.
        public let isEnd: Bool
    }

    /// 0 = Monday ... 6 = Sunday. 1970-01-01 was a Thursday.
    public static func weekdayIndex(_ iso: String) -> Int {
        ((DateUtils.dayNumber(iso) ?? 0) + 3) % 7
    }

    /// Mondays of the weeks that hold the days of the month starting on `month`.
    public static func weeks(ofMonth month: String) -> [String] {
        let first = DateUtils.addDays(month, -weekdayIndex(month))
        let last = DateUtils.addDays(DateUtils.addMonths(month, 1), -1)
        return stride(from: 0, through: DateUtils.daysBetween(first, last), by: 7).map { DateUtils.addDays(first, $0) }
    }

    /// Skip and gap markers come one per day; neighbours are joined so a trip
    /// draws as one bar.
    public static func joined(_ events: [CalendarEvent]) -> [CalendarEvent] {
        var result: [CalendarEvent] = []
        var last: [CalendarEvent.Kind: Int] = [:]
        for event in events {
            guard event.kind == .skip || event.kind == .gap else {
                result.append(event)
                continue
            }
            if let index = last[event.kind], result[index].end == event.start, result[index].title == event.title {
                result[index].end = event.end
            } else {
                last[event.kind] = result.count
                result.append(event)
            }
        }
        return result
    }

    /// The spans crossing one week, clipped to it and stacked into lanes.
    /// Override markers aren't spans and are left out.
    public static func segments(_ events: [CalendarEvent], week monday: String) -> [Segment] {
        let weekEnd = DateUtils.addDays(monday, 7)
        let crossing =
            events
            .filter { $0.kind != .override && $0.start < weekEnd && $0.end > monday }
            .sorted { $0.start < $1.start }
        var laneEnds: [Int] = []
        return crossing.map { event in
            let start = max(0, DateUtils.daysBetween(monday, event.start))
            let end = min(6, DateUtils.daysBetween(monday, event.end) - 1)
            let lane = laneEnds.firstIndex { $0 < start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(end) } else { laneEnds[lane] = end }
            return Segment(
                event: event, startColumn: start, endColumn: end, lane: lane,
                isStart: event.start >= monday, isEnd: event.end <= weekEnd
            )
        }
    }
}

/// What the app hands the widget: the schedule as calendar events and each
/// roaster's colour. The widget can't open the database, so the app writes
/// this as JSON into the App Group container they share.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let appGroup = "group.net.mattmargolis.CoffeeScheduler"
    public static let fileName = "widget-snapshot.json"

    /// Bag spans and skip and gap bars, already joined.
    public var events: [CalendarEvent]
    /// Roaster name to "#rrggbb".
    public var roasterColors: [String: String]

    public init(events: [CalendarEvent], roasterColors: [String: String]) {
        self.events = events
        self.roasterColors = roasterColors
    }

    public init(schedule: [ScheduleDay], skipRanges: [SkipRange], roasterColors: [String: RoasterColor]) {
        self.init(
            events: MonthGrid.joined(CalendarSpans.events(schedule: schedule, skipRanges: skipRanges)),
            roasterColors: roasterColors.mapValues(\.border)
        )
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public init(decoding data: Data) throws {
        self = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
