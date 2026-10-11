import CoffeeCore
import SwiftUI
import WidgetKit

/// The month grid at widget size: dates with each bag's bar beneath. The
/// large widget names the bags; the medium one has room only for the bars.
struct MonthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MonthEntry

    var body: some View {
        let month = DateUtils.firstOfMonth(entry.today)
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
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, letter in
                    Text(letter).frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: isLarge ? 10 : 8, weight: .semibold))
            .foregroundStyle(Palette.text3)
            .padding(.bottom, isLarge ? 4 : 2)

            ForEach(weeks, id: \.self) { monday in
                Palette.hairline.frame(height: 1)
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
        HStack(alignment: .firstTextBaseline) {
            Text(entry.date, format: .dateTime.month(.wide).year())
                .font(.system(size: isLarge ? 15 : 12, weight: .bold))
                .foregroundStyle(Palette.text)
            Spacer()
            if entry.snapshot == nil && isLarge {
                Text("Open the app to load the schedule")
                    .font(.system(size: isLarge ? 11 : 9))
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
            }
        }
        .padding(.bottom, isLarge ? 6 : 3)
    }
}

/// One week of the grid. The large widget puts the spans in up to two rows
/// under the dates; the medium one has no room for that, so each span is a
/// box behind its dates.
private struct WidgetWeek: View {
    let monday: String
    let month: String
    let today: String
    let segments: [MonthGrid.Segment]
    let colors: [String: String]
    let isLarge: Bool
    let labelsContinuations: Bool

    /// Where the bars go in a week of a given height.
    private struct Metrics {
        let dateHeight: CGFloat
        let barHeight: CGFloat
        let firstBar: CGFloat
        let laneHeight: CGFloat
        let lanes: Int
    }

    private func metrics(height: CGFloat) -> Metrics {
        if isLarge {
            // Only the rows of bars that fit under the dates
            return Metrics(dateHeight: 19, barHeight: 14, firstBar: 19, laneHeight: 16, lanes: max(1, Int((height - 19) / 16)))
        }
        // Two bags on one day share the box's height
        let lanes = min(2, max(1, (segments.map(\.lane).max() ?? 0) + 1))
        let lane = max(0, height - 3) / CGFloat(lanes)
        return Metrics(dateHeight: height, barHeight: lane, firstBar: 1.5, laneHeight: lane, lanes: lanes)
    }

    var body: some View {
        GeometryReader { geometry in
            let column = geometry.size.width / 7
            let metrics = metrics(height: geometry.size.height)
            ZStack(alignment: .topLeading) {
                ForEach(segments.filter { $0.lane < metrics.lanes }, id: \.self) { segment in
                    let lead: CGFloat = segment.isStart ? 1.5 : 0
                    let trail: CGFloat = segment.isEnd ? 1.5 : 0
                    WidgetBar(
                        segment: segment, color: color(segment.event), isLarge: isLarge,
                        showsTitle: isLarge && (segment.isStart || labelsContinuations)
                    )
                    .frame(
                        width: max(0, column * CGFloat(segment.endColumn - segment.startColumn + 1) - lead - trail),
                        height: metrics.barHeight
                    )
                    .offset(
                        x: column * CGFloat(segment.startColumn) + lead,
                        y: metrics.firstBar + CGFloat(segment.lane) * metrics.laneHeight)
                }
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { offset in
                        dateLabel(DateUtils.addDays(monday, offset), column: offset, height: metrics.dateHeight)
                            .frame(width: column, height: metrics.dateHeight)
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

    /// On the medium widget, a date over a brewed bag's solid box needs dark text.
    private func isOnSolidBox(column: Int) -> Bool {
        guard !isLarge else { return false }
        return segments.contains {
            $0.lane == 0 && $0.startColumn <= column && column <= $0.endColumn && $0.event.beanID != nil && $0.event.isActual
        }
    }

    @ViewBuilder
    private func dateLabel(_ date: String, column: Int, height: CGFloat) -> some View {
        let number = Text(String(Int(date.suffix(2)) ?? 0))
            .font(.system(size: isLarge ? 12 : 9, weight: isLarge ? .regular : .medium))
            .monospacedDigit()
        if date == today {
            let disc = min(17, height - 3)
            number
                .fontWeight(.bold)
                .foregroundStyle(Palette.ground)
                .frame(width: disc, height: disc)
                .background(Palette.accent, in: Circle())
        } else if isOnSolidBox(column: column) {
            number.foregroundStyle(Palette.ground)
        } else if DateUtils.firstOfMonth(date) != month {
            number.foregroundStyle(Palette.dim)
        } else {
            number.foregroundStyle(date < today ? Palette.text2 : Palette.text)
        }
    }
}

/// One span in a week: solid for brewed days, tinted and outlined for
/// projected ones, dashed for skipped days and days with no coffee.
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
            // The roaster colours are light, so a solid bar takes dark text
            if event.isActual { return Look(fill: color, stroke: .clear, text: Palette.ground) }
            return Look(fill: color.opacity(0.25), stroke: color, text: Palette.text)
        }
    }
}
