import CoffeeCore
import SwiftUI

/// The upcoming days, a week per card from the current week. A run of
/// skipped days, or of days with no coffee, is one row until it's tapped.
struct WeekList: View {
    @Environment(AppModel.self) private var model
    let openBean: (String) -> Void
    let openDay: (String) -> Void
    /// Days whose run is shown day by day rather than as one row.
    @State private var expanded: Set<String> = []

    var body: some View {
        let runs = Dictionary(Scheduler.bagRuns(model.schedule).map { ($0.beanID, $0) }, uniquingKeysWith: { a, _ in a })
        ForEach(weeks, id: \.first?.date) { week in
            Section {
                ForEach(Self.entries(week, today: model.today, expanded: expanded)) { entry in
                    switch entry {
                    case .day(let day): dayRow(day, runs: runs)
                    case .run(let run):
                        IdleRunRow(run: run, reason: run.kind == .skip ? model.skipReason(on: run.start) : nil) {
                            expanded.insert(run.start)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 14))
                .listRowSeparatorTint(Theme.hairline)
            } header: {
                SectionLabel(
                    title: Format.weekTitle(week.first!.date, today: model.today),
                    detail: Format.span(week.first!.date, week.last!.date)
                )
                .listRowInsets(Theme.labelInsets)
            }
        }
    }

    private func dayRow(_ day: ScheduleDay, runs: [String: BagRun]) -> some View {
        DayRow(day: day, runs: runs, openBean: openBean, openDay: { openDay(day.date) })
            .swipeActions(edge: .leading) {
                Button {
                    // Keep the day on screen if skipping joins it to a run
                    expanded.insert(day.date)
                    model.toggleSkipDay(day.date)
                } label: {
                    Label(day.isSkip ? "Don't skip" : "Skip", systemImage: day.isSkip ? "cup.and.saucer" : "airplane")
                }
                .tint(day.isSkip ? .green : .indigo)
            }
    }

    /// Days from the start of this week (Monday) onward, chunked by week.
    private var weeks: [[ScheduleDay]] {
        let weekday = Format.weekdayIndex(model.today)  // 0 = Monday
        let start = DateUtils.addDays(model.today, -weekday)
        let upcoming = model.schedule.filter { $0.date >= start }
        return stride(from: 0, to: upcoming.count, by: 7).map {
            Array(upcoming[$0..<min($0 + 7, upcoming.count)])
        }
    }
}

/// Two or more days in a row with nothing to drink, for the same reason.
struct IdleRun: Hashable {
    enum Kind: Hashable { case skip, gap }
    let kind: Kind
    let days: [ScheduleDay]

    var start: String { days.first?.date ?? "" }
    var end: String { days.last?.date ?? "" }
}

extension WeekList {
    enum Entry: Identifiable {
        case day(ScheduleDay)
        case run(IdleRun)

        var id: String {
            switch self {
            case .day(let day): day.date
            case .run(let run): "run-\(run.start)"
            }
        }
    }

    /// A week's rows: its days, with each run of idle days folded into one
    /// row unless it holds today or a day in `expanded`.
    static func entries(_ week: [ScheduleDay], today: String, expanded: Set<String>) -> [Entry] {
        var entries: [Entry] = []
        var index = 0
        while index < week.count {
            let kind = idleKind(week[index])
            var end = index + 1
            while kind != nil, end < week.count, idleKind(week[end]) == kind { end += 1 }
            let days = Array(week[index..<end])
            let isOpen = days.contains { $0.date == today || expanded.contains($0.date) }
            if let kind, days.count > 1, !isOpen {
                entries.append(.run(IdleRun(kind: kind, days: days)))
            } else {
                entries += days.map(Entry.day)
            }
            index = end
        }
        return entries
    }

    private static func idleKind(_ day: ScheduleDay) -> IdleRun.Kind? {
        if day.isSkip { return .skip }
        return day.isGap && !day.isActual ? .gap : nil
    }
}

/// A run of idle days as one dashed row; tapping it shows the days.
private struct IdleRunRow: View {
    let run: IdleRun
    /// What the skip is for, when its range has a reason.
    let reason: String?
    let expand: () -> Void

    var body: some View {
        let isSkip = run.kind == .skip
        Button(action: expand) {
            HStack(spacing: 12) {
                Image(systemName: isSkip ? "airplane" : "exclamationmark.triangle")
                    .frame(width: DayRow.dateWidth)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isSkip ? reason ?? "Skipped" : "No coffee")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("\(day(run.start)) – \(day(run.end)) · \(isSkip ? "skipped" : "nothing ready")")
                        .font(.caption)
                }
                Spacer(minLength: 8)
                Text(Format.days(run.days.count)).font(.footnote.weight(.semibold)).monospacedDigit()
            }
            .foregroundStyle(isSkip ? Theme.text2 : Theme.gapText)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows each day")
        .listRowBackground(RowCard(tile: isSkip ? .skipped : .gap))
        .listRowSeparator(.hidden)
    }

    private func day(_ date: String) -> String {
        "\(Format.weekday(date)) \(Format.dayNumber(date))"
    }
}
