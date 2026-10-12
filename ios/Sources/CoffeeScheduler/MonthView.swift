import CoffeeCore
import SwiftUI

/// A month grid with bag spans, the layout the schedule opens on. Each bag is a bar in its
/// roaster's colour across the days it runs, solid for brewed days and
/// outlined for projected ones; skipped days and days with no coffee are
/// dashed bars. Tap a bar for the bag, a date for its options.
struct MonthView: View {
    @Environment(AppModel.self) private var model
    /// First of the month shown.
    @Binding var month: String
    let openBean: (String) -> Void
    let openDay: (String) -> Void
    /// The title, the arrows and the share button; left out of a shared picture.
    var showsHeader = true

    var body: some View {
        let events = MonthGrid.joined(
            CalendarSpans.events(schedule: model.schedule, skipRanges: model.skipRanges, overrides: model.consumptionOverrides)
        )
        let days = Dictionary(model.schedule.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })

        VStack(spacing: 0) {
            if showsHeader { header }
            HStack(spacing: 0) {
                ForEach(Array(MonthGrid.weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter).frame(maxWidth: .infinity)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.text3)
            .padding(.vertical, 10)

            ForEach(weeks, id: \.self) { monday in
                Theme.weekLine.frame(height: 1)
                WeekRow(
                    monday: monday, month: month,
                    segments: MonthGrid.segments(events, week: monday),
                    days: days,
                    // A bag running on from last month still needs its name
                    labelsContinuations: monday == weeks.first,
                    openBean: openBean, openDay: openDay
                )
            }
        }
    }

    private var header: some View {
        HStack {
            step(-1, icon: "chevron.left", label: "Previous month")
                .disabled(month <= firstMonth)
            Spacer()
            // As wide as the share button, so the title stays in the middle
            Color.clear.frame(width: 44, height: 1)
            Text(Format.monthTitle(month)).font(.headline.bold())
            ShareScheduleLink(subject: .month(month)).buttonStyle(.plain)
            Spacer()
            step(1, icon: "chevron.right", label: "Next month")
                .disabled(month >= lastMonth)
        }
    }

    private func step(_ months: Int, icon: String, label: String) -> some View {
        Button {
            month = DateUtils.addMonths(month, months)
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Theme.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var firstMonth: String { model.schedule.first.map { DateUtils.firstOfMonth($0.date) } ?? month }
    private var lastMonth: String { model.schedule.last.map { DateUtils.firstOfMonth($0.date) } ?? month }

    private var weeks: [String] { MonthGrid.weeks(ofMonth: month) }
}

private struct WeekRow: View {
    @Environment(AppModel.self) private var model
    let monday: String
    let month: String
    let segments: [MonthGrid.Segment]
    let days: [String: ScheduleDay]
    let labelsContinuations: Bool
    let openBean: (String) -> Void
    let openDay: (String) -> Void

    private static let dateHeight: CGFloat = 32
    private static let barHeight: CGFloat = 22
    private static let laneHeight: CGFloat = 26
    private static let overrideHeight: CGFloat = 14

    var body: some View {
        let lanes = max(1, (segments.map(\.lane).max() ?? -1) + 1)
        let dates = (0..<7).map { DateUtils.addDays(monday, $0) }
        let hasOverride = dates.contains { overrideLabel($0) != nil }
        GeometryReader { geometry in
            let column = geometry.size.width / 7
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(dates, id: \.self) { date in
                        cell(date).frame(width: column)
                    }
                }
                ForEach(segments, id: \.self) { segment in
                    // A gap at each end the span really ends on; flush where it runs on
                    let lead: CGFloat = segment.isStart ? 2 : 0
                    let trail: CGFloat = segment.isEnd ? 2 : 0
                    MonthBar(
                        segment: segment, color: color(segment.event),
                        showsTitle: segment.isStart || labelsContinuations, openBean: openBean
                    )
                    .frame(
                        width: max(0, column * CGFloat(segment.endColumn - segment.startColumn + 1) - lead - trail),
                        height: Self.barHeight
                    )
                    .offset(
                        x: column * CGFloat(segment.startColumn) + lead,
                        y: Self.dateHeight + CGFloat(segment.lane) * Self.laneHeight)
                }
            }
        }
        .frame(height: Self.dateHeight + CGFloat(lanes) * Self.laneHeight + (hasOverride ? Self.overrideHeight : 0) + 2)
    }

    private func color(_ event: CalendarEvent) -> Color {
        if case .bean(_, let roaster) = event.kind { return model.rail(roaster) }
        return Theme.dim
    }

    /// "60 g" for a day with its own amount, unless the day is skipped.
    private func overrideLabel(_ date: String) -> String? {
        guard days[date]?.isSkip == false, let override = model.consumptionOverride(on: date) else { return nil }
        return "\(Format.grams(override.dailyGrams)) g"
    }

    private func cell(_ date: String) -> some View {
        let day = days[date]
        return VStack(spacing: 0) {
            // The button is only the date, so its middle is clear of the bars
            Button {
                openDay(date)
            } label: {
                dateLabel(date, isSkip: day?.isSkip == true)
                    .frame(maxWidth: .infinity, minHeight: Self.dateHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Format.longDay(date))
            .accessibilityIdentifier("month-day-\(date)")
            Spacer(minLength: 0)
            if let label = overrideLabel(date) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .frame(height: Self.overrideHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The rest of the cell opens the day too, where no bag's bar covers it
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { if day != nil { openDay(date) } }
                .accessibilityHidden(true)
        }
        .disabled(day == nil)
    }

    @ViewBuilder
    private func dateLabel(_ date: String, isSkip: Bool) -> some View {
        let number = Text(Format.dayNumber(date)).font(.system(size: 14)).monospacedDigit()
        if date == model.today {
            number
                .fontWeight(.bold)
                .foregroundStyle(Theme.ground)
                .frame(width: 26, height: 26)
                .background(Theme.accent, in: Circle())
        } else if DateUtils.firstOfMonth(date) != month {
            number.foregroundStyle(Theme.dim)
        } else if isSkip {
            number.foregroundStyle(Theme.text3)
        } else {
            number.foregroundStyle(date < model.today ? Theme.text2 : Theme.text)
        }
    }
}

/// One span in a week of the grid.
private struct MonthBar: View {
    let segment: MonthGrid.Segment
    /// The roaster's colour, for a bag.
    let color: Color
    let showsTitle: Bool
    let openBean: (String) -> Void

    var body: some View {
        let event = segment.event
        if let id = event.beanID {
            Button {
                openBean(id)
            } label: {
                face
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(event.title), \(event.meta ?? "")")
        } else {
            // Taps fall through to the days underneath
            face.allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private var face: some View {
        let lead: CGFloat = segment.isStart ? 7 : 0
        let trail: CGFloat = segment.isEnd ? 7 : 0
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: lead, bottomLeadingRadius: lead, bottomTrailingRadius: trail, topTrailingRadius: trail
        )
        let look = self.look
        return Text(showsTitle ? segment.event.title : "")
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(look.text)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(shape.fill(look.fill))
            .overlay(shape.strokeBorder(look.stroke, style: look.isDashed ? Theme.dash : StrokeStyle(lineWidth: 1)))
            .contentShape(Rectangle())
    }

    private struct Look {
        let fill: Color
        let stroke: Color
        let text: Color
        var isDashed = false
    }

    private var look: Look {
        let event = segment.event
        switch event.kind {
        case .skip:
            return Look(fill: .clear, stroke: Theme.dim, text: Theme.text2, isDashed: true)
        case .gap:
            return Look(fill: Theme.gap.opacity(0.14), stroke: Theme.gap, text: Theme.gapText, isDashed: true)
        default:
            // Brewed days are solid; projected ones tinted and outlined
            // The roaster colours are light, so a solid bar takes dark text
            if event.isActual { return Look(fill: color, stroke: .clear, text: Theme.ground) }
            let isEarly = event.daysEarly > 0 && segment.isStart
            return Look(fill: color.opacity(0.2), stroke: color, text: isEarly ? Theme.accent : Theme.text)
        }
    }
}
