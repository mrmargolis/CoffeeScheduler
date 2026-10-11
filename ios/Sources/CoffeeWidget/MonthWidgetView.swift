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
        let weeks = MonthGrid.weeks(ofMonth: month)
        let isLarge = family == .systemLarge
        VStack(spacing: 0) {
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
            if entry.snapshot == nil {
                Text("Open the app to load the schedule")
                    .font(.system(size: isLarge ? 11 : 9))
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
            }
        }
        .padding(.bottom, isLarge ? 6 : 3)
    }
}

/// One week: the dates, then the spans crossing it in up to two rows.
private struct WidgetWeek: View {
    let monday: String
    let month: String
    let today: String
    let segments: [MonthGrid.Segment]
    let colors: [String: String]
    let isLarge: Bool
    let labelsContinuations: Bool

    private var dateHeight: CGFloat { isLarge ? 19 : 13 }
    private var barHeight: CGFloat { isLarge ? 14 : 4 }
    private var laneHeight: CGFloat { barHeight + 2 }

    var body: some View {
        GeometryReader { geometry in
            let column = geometry.size.width / 7
            // Only the rows of bars that fit under the dates
            let lanes = max(1, Int((geometry.size.height - dateHeight) / laneHeight))
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { offset in
                        dateLabel(DateUtils.addDays(monday, offset)).frame(width: column, height: dateHeight)
                    }
                }
                ForEach(segments.filter { $0.lane < lanes }, id: \.self) { segment in
                    let lead: CGFloat = segment.isStart ? 1.5 : 0
                    let trail: CGFloat = segment.isEnd ? 1.5 : 0
                    WidgetBar(
                        segment: segment, color: color(segment.event), isLarge: isLarge,
                        showsTitle: isLarge && (segment.isStart || labelsContinuations)
                    )
                    .frame(
                        width: max(0, column * CGFloat(segment.endColumn - segment.startColumn + 1) - lead - trail),
                        height: barHeight
                    )
                    .offset(x: column * CGFloat(segment.startColumn) + lead, y: dateHeight + CGFloat(segment.lane) * laneHeight)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func color(_ event: CalendarEvent) -> Color {
        guard case .bean(_, let roaster) = event.kind else { return Palette.dim }
        return Color(hex: colors[roaster] ?? RoasterColor.forRoaster(roaster).border)
    }

    @ViewBuilder
    private func dateLabel(_ date: String) -> some View {
        let number = Text(String(Int(date.suffix(2)) ?? 0))
            .font(.system(size: isLarge ? 12 : 9))
            .monospacedDigit()
        if date == today {
            number
                .fontWeight(.bold)
                .foregroundStyle(Palette.ground)
                .frame(width: dateHeight - 2, height: dateHeight - 2)
                .background(Palette.accent, in: Circle())
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
        let radius: CGFloat = isLarge ? 4.5 : 2
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
