import AppIntents
import CoffeeCore
import SwiftUI
import WidgetKit

/// The month grid at widget size. The large widget puts a named bar per bag
/// under the dates; the medium one draws each bag as a box behind its dates
/// and lists the bags beside the grid.
struct MonthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MonthEntry

    var body: some View {
        let month = entry.month
        if family == .systemLarge {
            grid(month: month, isLarge: true)
        } else {
            // No room for names on the bars, so the bags are listed beside the grid
            GeometryReader { geometry in
                HStack(spacing: 12) {
                    grid(month: month, isLarge: false).frame(width: geometry.size.width * 0.52)
                    BagList(bags: MonthBag.upcoming(entry.snapshot?.events ?? [], month: month, today: entry.today), entry: entry)
                }
            }
        }
    }

    private func grid(month: String, isLarge: Bool) -> some View {
        let weeks = MonthGrid.weeks(ofMonth: month)
        return VStack(spacing: 0) {
            header(isLarge: isLarge)
            HStack(spacing: 0) {
                ForEach(Array(MonthGrid.weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter).frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: isLarge ? 10 : 8, weight: .semibold))
            .foregroundStyle(Palette.text3)
            .padding(.bottom, isLarge ? 4 : 2)

            ForEach(weeks, id: \.self) { monday in
                Palette.weekLine.frame(height: 1)
                WidgetWeek(
                    monday: monday, month: month, today: entry.today,
                    segments: MonthGrid.segments(entry.snapshot?.events ?? [], week: monday),
                    colors: entry.snapshot?.roasterColors ?? [:],
                    isLarge: isLarge,
                    // A bag running on from last month still needs its name
                    labelsContinuations: monday == weeks.first
                )
            }
        }
    }

    private func header(isLarge: Bool) -> some View {
        HStack(spacing: isLarge ? 6 : 2) {
            arrow(-1, icon: "chevron.left", isLarge: isLarge)
            // The title goes back to the current month
            Button(intent: ShiftMonthIntent(months: 0)) {
                Text(Self.title(entry.month))
                    .font(.system(size: isLarge ? 15 : 12, weight: .bold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.plain)
            arrow(1, icon: "chevron.right", isLarge: isLarge)
            Spacer(minLength: 0)
            if entry.snapshot == nil && isLarge {
                Text("Open the app to load the schedule")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
            }
        }
        .padding(.bottom, isLarge ? 6 : 3)
    }

    private func arrow(_ months: Int, icon: String, isLarge: Bool) -> some View {
        let isEnabled = ShownMonth.canMove(months, today: entry.today)
        return Button(intent: ShiftMonthIntent(months: months)) {
            Image(systemName: icon)
                .font(.system(size: isLarge ? 12 : 10, weight: .bold))
                .foregroundStyle(isEnabled ? Palette.accent : Palette.dim)
                .frame(width: isLarge ? 28 : 20, height: isLarge ? 24 : 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(months < 0 ? "Previous month" : "Next month")
    }

    /// "October 2026" for the first of a month, read in UTC so it can't shift.
    private static func title(_ month: String) -> String {
        var style = Date.FormatStyle.dateTime.month(.wide).year()
        style.timeZone = TimeZone(identifier: "UTC") ?? .current
        return DateUtils.noonUTC(month).formatted(style)
    }
}

/// One week of the grid. The large widget puts the spans in rows under the
/// dates; the medium one has no room for that, so each span is a box behind
/// its dates.
private struct WidgetWeek: View {
    let monday: String
    let month: String
    let today: String
    let segments: [MonthGrid.Segment]
    let colors: [String: String]
    let isLarge: Bool
    let labelsContinuations: Bool

    private static let largeDateHeight: CGFloat = 19
    private static let largeLaneHeight: CGFloat = 16

    /// Where a span is drawn in a week of the given size.
    private func frame(_ segment: MonthGrid.Segment, column: CGFloat, height: CGFloat) -> CGRect {
        let lead: CGFloat = segment.isStart ? 1.5 : 0
        let trail: CGFloat = segment.isEnd ? 1.5 : 0
        let left = column * CGFloat(segment.startColumn) + lead
        let width = max(0, column * CGFloat(segment.endColumn - segment.startColumn + 1) - lead - trail)
        if isLarge {
            let lane = largeLaneHeight(height: height)
            return CGRect(x: left, y: Self.largeDateHeight + CGFloat(segment.lane) * lane, width: width, height: lane - 2)
        }
        // Medium: every box is the full height of the week, so they line
        // up. Bags that share a day stand side by side in it.
        let sharing = segments.filter { $0.startColumn <= segment.endColumn && segment.startColumn <= $0.endColumn }
        let place = CGFloat(sharing.firstIndex(of: segment) ?? 0)
        let share = width / CGFloat(max(1, sharing.count))
        return CGRect(x: left + place * share, y: 1.5, width: share, height: max(0, height - 3))
    }

    /// The large widget's rows of bars are squeezed, when a week has more
    /// bags on one day than fit under the dates, so that none is left out.
    private func largeLaneHeight(height: CGFloat) -> CGFloat {
        let lanes = CGFloat((segments.map(\.lane).max() ?? 0) + 1)
        return min(Self.largeLaneHeight, max(0, height - Self.largeDateHeight) / lanes)
    }

    var body: some View {
        GeometryReader { geometry in
            let column = geometry.size.width / 7
            let height = geometry.size.height
            let dateHeight = isLarge ? Self.largeDateHeight : height
            // A squeezed bar is too short for its name
            let fitsTitles = isLarge && largeLaneHeight(height: height) >= 13
            ZStack(alignment: .topLeading) {
                ForEach(segments, id: \.self) { segment in
                    let rect = frame(segment, column: column, height: height)
                    WidgetBar(
                        segment: segment, color: color(segment.event), isLarge: isLarge,
                        showsTitle: fitsTitles && (segment.isStart || labelsContinuations)
                    )
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                }
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { offset in
                        dateLabel(DateUtils.addDays(monday, offset), column: offset, height: dateHeight)
                            .frame(width: column, height: dateHeight)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func color(_ event: CalendarEvent) -> Color {
        guard case .bean(_, let roaster) = event.kind else { return Palette.dim }
        return Color(hex: colors[roaster] ?? RoasterColor.forRoaster(roaster).border)
    }

    /// On the medium widget, a date over a bag's solid box needs dark text.
    /// Only brewed days are solid; a projected day's box is a tint.
    private func isOnSolidBox(column: Int) -> Bool {
        guard !isLarge else { return false }
        return segments.contains {
            $0.startColumn <= column && column <= $0.endColumn && $0.event.beanID != nil && $0.event.isActual
        }
    }

    @ViewBuilder
    private func dateLabel(_ date: String, column: Int, height: CGFloat) -> some View {
        let number = Text(String(Int(date.suffix(2)) ?? 0))
            .font(.system(size: isLarge ? 12 : 9, weight: isLarge ? .regular : .medium))
            .monospacedDigit()
        if date == today && isLarge {
            number
                .fontWeight(.bold)
                .foregroundStyle(Palette.ground)
                .frame(width: 17, height: 17)
                .background(Palette.accent, in: Circle())
        } else if date == today {
            // An outline round the day's box, so the bag's colour still shows
            number
                .fontWeight(.bold)
                .foregroundStyle(isOnSolidBox(column: column) ? Palette.ground : Palette.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Cream with a dark line inside it: gold alone gets lost
                // against the roaster colours
                .overlay(
                    ZStack {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.text, lineWidth: 2)
                        RoundedRectangle(cornerRadius: 2.5).strokeBorder(Palette.ground, lineWidth: 1).padding(2)
                    }
                    .padding(0.5)
                )
        } else if isOnSolidBox(column: column) {
            number.foregroundStyle(Palette.ground)
        } else if DateUtils.firstOfMonth(date) != month {
            number.foregroundStyle(Palette.dim)
        } else {
            number.foregroundStyle(date < today ? Palette.text2 : Palette.text)
        }
    }
}

/// One span in a week, shaded as in the app's month view: a bag is solid in
/// its roaster's colour for brewed days and a tint of it with an outline for
/// projected ones; skipped days and days with no coffee are dashed.
private struct WidgetBar: View {
    let segment: MonthGrid.Segment
    let color: Color
    let isLarge: Bool
    let showsTitle: Bool

    var body: some View {
        let radius: CGFloat = isLarge ? 4.5 : 4
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: segment.isStart ? radius : 0, bottomLeadingRadius: segment.isStart ? radius : 0,
            bottomTrailingRadius: segment.isEnd ? radius : 0, topTrailingRadius: segment.isEnd ? radius : 0
        )
        let look = self.look
        Text(showsTitle ? segment.event.title : "")
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(look.text)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(shape.fill(look.fill))
            .overlay(shape.strokeBorder(look.stroke, style: StrokeStyle(lineWidth: isLarge ? 1 : 0.75, dash: look.dash)))
    }

    private struct Look {
        let fill: Color
        let stroke: Color
        let text: Color
        var dash: [CGFloat] = []
    }

    private var look: Look {
        let event = segment.event
        switch event.kind {
        case .skip:
            return Look(fill: .clear, stroke: Palette.dim, text: Palette.text2, dash: [3, 2])
        case .gap:
            return Look(fill: Palette.gap.opacity(0.14), stroke: Palette.gap, text: Palette.gapText, dash: [3, 2])
        default:
            // As in the app: brewed days are solid, projected ones tinted
            // and outlined. The roaster colours are light, so a solid bar
            // takes dark text
            if event.isActual { return Look(fill: color, stroke: .clear, text: Palette.ground) }
            let isEarly = event.daysEarly > 0 && segment.isStart
            return Look(fill: color.opacity(0.2), stroke: color, text: isEarly ? Palette.accent : Palette.text)
        }
    }
}
