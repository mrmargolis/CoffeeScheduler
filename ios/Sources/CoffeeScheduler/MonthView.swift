import CoffeeCore
import SwiftUI

/// A month grid with bag spans, the alternative to the week list. Mirrors the
/// web app's calendar (`src/components/Calendar.tsx`): each bag is a bar in its
/// roaster's colour across the days it runs, broken at skip days and where
/// brewed days meet projected ones. Tap a bar for the bag, a date for its options.
struct MonthView: View {
    @Environment(AppModel.self) private var model
    /// First of the month shown.
    @Binding var month: String
    let openBean: (String) -> Void
    let openDay: (String) -> Void

    var body: some View {
        let events = CalendarSpans.events(
            schedule: model.schedule, skipRanges: model.skipRanges, overrides: model.consumptionOverrides
        )
        let days = Dictionary(model.schedule.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let overrideDays = Set(events.filter { $0.kind == .override }.map(\.start))

        VStack(spacing: 6) {
            header
            HStack(spacing: 0) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, letter in
                    Text(letter).frame(maxWidth: .infinity)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(weeks, id: \.self) { monday in
                WeekRow(
                    monday: monday, month: month, today: model.today,
                    segments: Self.segments(events, week: monday),
                    days: days, overrideDays: overrideDays,
                    rail: model.rail, openBean: openBean, openDay: openDay
                )
            }
        }
    }

    private var header: some View {
        HStack {
            Button { month = DateUtils.addMonths(month, -1) } label: {
                Image(systemName: "chevron.left").padding(6)
            }
            .accessibilityLabel("Previous month")
            .disabled(month <= firstMonth)
            Spacer()
            Text(Format.monthTitle(month)).font(.headline)
            Spacer()
            Button { month = DateUtils.addMonths(month, 1) } label: {
                Image(systemName: "chevron.right").padding(6)
            }
            .accessibilityLabel("Next month")
            .disabled(month >= lastMonth)
        }
        .buttonStyle(.borderless)
    }

    private var firstMonth: String { model.schedule.first.map { DateUtils.firstOfMonth($0.date) } ?? month }
    private var lastMonth: String { model.schedule.last.map { DateUtils.firstOfMonth($0.date) } ?? month }

    /// Mondays of the weeks that hold this month's days.
    private var weeks: [String] {
        let first = DateUtils.addDays(month, -Format.weekdayIndex(month))
        let last = DateUtils.addDays(DateUtils.addMonths(month, 1), -1)
        return stride(from: 0, through: DateUtils.daysBetween(first, last), by: 7).map { DateUtils.addDays(first, $0) }
    }

    struct Segment: Hashable {
        let event: CalendarEvent
        let startColumn: Int
        let endColumn: Int // inclusive
        let lane: Int
        /// The bag's span begins in this week (as opposed to continuing from the last).
        let isStart: Bool
    }

    /// The bag spans crossing one week, clipped to it and stacked into lanes.
    static func segments(_ events: [CalendarEvent], week monday: String) -> [Segment] {
        let weekEnd = DateUtils.addDays(monday, 7)
        let crossing = events
            .filter { $0.beanID != nil && $0.start < weekEnd && $0.end > monday }
            .sorted { $0.start < $1.start }
        var laneEnds: [Int] = []
        return crossing.map { event in
            let start = max(0, DateUtils.daysBetween(monday, event.start))
            let end = min(6, DateUtils.daysBetween(monday, event.end) - 1)
            let lane = laneEnds.firstIndex { $0 < start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(end) } else { laneEnds[lane] = end }
            return Segment(event: event, startColumn: start, endColumn: end, lane: lane, isStart: event.start >= monday)
        }
    }
}

private struct WeekRow: View {
    let monday: String
    let month: String
    let today: String
    let segments: [MonthView.Segment]
    let days: [String: ScheduleDay]
    let overrideDays: Set<String>
    let rail: (String) -> Color
    let openBean: (String) -> Void
    let openDay: (String) -> Void

    private static let dateHeight: CGFloat = 24
    private static let laneHeight: CGFloat = 18

    var body: some View {
        let lanes = max(1, (segments.map(\.lane).max() ?? -1) + 1)
        GeometryReader { geometry in
            let column = geometry.size.width / 7
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        cell(DateUtils.addDays(monday, col))
                            .frame(width: column)
                    }
                }
                ForEach(segments, id: \.self) { segment in
                    bar(segment)
                        .frame(width: column * CGFloat(segment.endColumn - segment.startColumn + 1) - 2,
                               height: Self.laneHeight - 3)
                        .offset(x: column * CGFloat(segment.startColumn) + 1,
                                y: Self.dateHeight + CGFloat(segment.lane) * Self.laneHeight)
                }
            }
        }
        .frame(height: Self.dateHeight + CGFloat(lanes) * Self.laneHeight + 4)
    }

    private func cell(_ date: String) -> some View {
        let inMonth = DateUtils.firstOfMonth(date) == month
        let day = days[date]
        let isGap = day.map { $0.isGap && !$0.isActual } ?? false
        return Button { openDay(date) } label: {
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Text(String(Int(date.suffix(2)) ?? 0))
                        .font(.caption.monospacedDigit().weight(date == today ? .bold : .regular))
                        .foregroundStyle(date == today ? Color.white : inMonth ? Color.primary : Color.secondary)
                        .frame(minWidth: 20, minHeight: 20)
                        .background { if date == today { Circle().fill(Color.accentColor) } }
                    if overrideDays.contains(date) {
                        Circle().fill(.orange).frame(width: 5, height: 5)
                    }
                }
                if day?.isSkip == true {
                    Image(systemName: "airplane").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isGap ? Color.red.opacity(0.15) : Color.clear)
            .opacity(inMonth ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day == nil)
        .accessibilityLabel(Format.longDay(date))
        .accessibilityIdentifier("month-day-\(date)")
    }

    private func bar(_ segment: MonthView.Segment) -> some View {
        let event = segment.event
        guard case .bean(let id, let roaster) = event.kind else { return AnyView(EmptyView()) }
        let color = rail(roaster)
        return AnyView(
            Button { openBean(id) } label: {
                HStack(spacing: 3) {
                    if segment.isStart { RoasterRail(color: color, height: Self.laneHeight - 7) }
                    Text(event.title)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(event.daysEarly > 0 && segment.isStart ? Color.orange : Color.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(event.isActual ? 0.2 : 0.4)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(event.title), \(event.meta ?? "")")
        )
    }
}

/// Which bag runs over which dates, in the order they're drunk. Port of the
/// published page's bag list (`collectBagRuns`); tapping a bag opens it.
struct BagKey: View {
    @Environment(AppModel.self) private var model
    let runs: [BagRun]
    let openBean: (String) -> Void

    var body: some View {
        ForEach(runs, id: \.beanID) { run in
            Button { openBean(run.beanID) } label: {
                HStack(spacing: 8) {
                    RoasterRail(color: model.rail(run.roaster), height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(run.name).lineLimit(1)
                        Text(run.roaster).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(run.start == run.end
                             ? Format.shortDay(run.start)
                             : "\(Format.shortDay(run.start)) – \(Format.shortDay(run.end))")
                        if let ages = model.ageRanges[run.beanID] {
                            Text(Format.ages(ages))
                                .foregroundStyle(ages.finish > BeanDetail.oldFinishAge ? Color.red : Color.secondary)
                                .accessibilityLabel("Age \(Format.ages(ages))")
                        }
                        Text("\(Format.grams(run.grams.rounded())) g")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.monospacedDigit())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
