import CoffeeCore
import SwiftUI
import UniformTypeIdentifiers

/// A month grid with the bag key, or a list of upcoming days, a week per
/// section starting with the current week.
struct ScheduleView: View {
    enum Layout: Hashable { case list, month }

    @Environment(AppModel.self) private var model
    @State private var pickingFolder = false
    @State private var path: [BeanRoute] = []
    @State private var dayOptions: DayRoute?
    @State private var layout: Layout
    /// First of the month the grid shows; nil for the current month.
    @State private var month: String?

    init(layout: Layout = .month) {
        _layout = State(initialValue: layout)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !model.hasFolder {
                    Section {
                        FolderPrompt { pickingFolder = true }
                    }
                }
                if !model.schedule.isEmpty {
                    Picker("Layout", selection: $layout) {
                        Text("List").tag(Layout.list)
                        Text("Month").tag(Layout.month)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if layout == .month && !model.schedule.isEmpty {
                    monthSections
                } else {
                    weekSections
                }
            }
            .navigationTitle("Schedule")
            .navigationDestination(for: BeanRoute.self) { BeanDetailView(beanID: $0.id) }
            .sheet(item: $dayOptions) { day in
                NavigationStack { DayOptionsSheet(date: day.date) }
                    .presentationDetents([.medium, .large])
            }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { model.chooseFolder(url) }
            }
            .overlay {
                if model.schedule.isEmpty {
                    ContentUnavailableView(
                        "No beans yet",
                        systemImage: "cup.and.saucer",
                        description: Text("Share a BeanConqueror export to this app, or import one from Settings.")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var weekSections: some View {
        ForEach(weeks, id: \.first?.date) { week in
            Section(Format.weekTitle(week.first!.date, today: model.today)) {
                ForEach(week) { day in
                    DayRow(
                        day: day,
                        isToday: day.date == model.today,
                        override: model.consumptionOverride(on: day.date),
                        openBean: { path.append(BeanRoute(id: $0)) },
                        openDay: { dayOptions = DayRoute(date: day.date) }
                    )
                    .swipeActions(edge: .leading) {
                        Button {
                            model.toggleSkipDay(day.date)
                        } label: {
                            Label(day.isSkip ? "Don't skip" : "Skip", systemImage: day.isSkip ? "cup.and.saucer" : "airplane")
                        }
                        .tint(day.isSkip ? .green : .indigo)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var monthSections: some View {
        let shown = Binding(
            get: { month ?? DateUtils.firstOfMonth(model.today) },
            set: { month = $0 }
        )
        let monthEnd = DateUtils.addDays(DateUtils.addMonths(shown.wrappedValue, 1), -1)
        Section {
            MonthView(
                month: shown,
                openBean: { path.append(BeanRoute(id: $0)) },
                openDay: { dayOptions = DayRoute(date: $0) }
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
        }
        let runs = Scheduler.bagRuns(model.schedule)
            .filter { $0.start <= monthEnd && $0.end >= shown.wrappedValue }
        if !runs.isEmpty {
            Section("Bags this month") {
                BagKey(runs: runs) { path.append(BeanRoute(id: $0)) }
            }
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

private struct DayRow: View {
    @Environment(AppModel.self) private var model
    let day: ScheduleDay
    let isToday: Bool
    let override: ConsumptionOverride?
    let openBean: (String) -> Void
    let openDay: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            // The date opens the day's options; the bags open their detail
            Button(action: openDay) {
                VStack(alignment: .leading) {
                    Text(Format.weekday(day.date)).font(.subheadline.weight(isToday ? .bold : .regular))
                    Text(Format.shortDay(day.date)).font(.caption).foregroundStyle(.secondary)
                    if let override, !day.isSkip, !day.isActual {
                        Text("\(Format.grams(override.dailyGrams))g day")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
                .frame(width: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Day options")
            .accessibilityIdentifier("day-\(day.date)")
            .accessibilityValue(accessibilityState)

            VStack(alignment: .leading, spacing: 2) {
                if day.isSkip {
                    // An HStack, not a Label: a Label sets the row's separator
                    // inset and draws its icon at title size
                    HStack(spacing: 6) {
                        Image(systemName: "airplane").font(.caption)
                        Text("Skipped")
                    }
                    .foregroundStyle(.secondary)
                } else if day.isGap && day.isActual {
                    // A past day nothing was logged for: not an alarm
                    Text("No brews logged").foregroundStyle(.tertiary)
                } else if day.isGap {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle").font(.caption)
                        Text("No coffee")
                    }
                    .foregroundStyle(.red)
                }
                ForEach(day.consumptions, id: \.beanID) { c in
                    // One button per bag: a day can hold two, and a row-wide
                    // link couldn't tell them apart.
                    Button {
                        openBean(c.beanID)
                    } label: {
                        HStack(spacing: 6) {
                            RoasterRail(color: model.rail(c.roaster))
                            Text(c.beanName).lineLimit(1).foregroundStyle(.primary)
                            if let early = c.daysEarly {
                                Text("\(early)d early").font(.caption).foregroundStyle(.orange)
                            }
                            Spacer()
                            Text("\(Format.grams(c.grams))g").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    // Plain, not borderless: borderless tints the label blue
                    .buttonStyle(.plain)
                }
            }
        }
        .opacity(day.isActual && !isToday ? 0.6 : 1)
        .listRowBackground(isToday ? Color.accentColor.opacity(0.12) : nil)
    }
}

extension DayRow {
    /// What VoiceOver (and the UI tests) read for a day besides its date.
    var accessibilityState: String {
        var parts: [String] = []
        if day.isSkip { parts.append("Skipped") }
        if let override, !day.isSkip { parts.append("\(Format.grams(override.dailyGrams))g day") }
        if day.isGap && !day.isActual { parts.append("No coffee") }
        return parts.joined(separator: ", ")
    }
}

@MainActor
enum Format {
    static func date(_ iso: String) -> Date {
        // Noon UTC rendered in UTC, so the calendar day can't shift.
        Date(timeIntervalSince1970: Double(DateUtils.dayNumber(iso) ?? 0) * 86_400 + 43_200)
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let weekdayFormatter = formatter("EEE")
    private static let shortDayFormatter = formatter("MMM d")
    private static let mediumDayFormatter = formatter("MMM d, yyyy")
    private static let longDayFormatter = formatter("EEEE MMMM d")
    private static let monthFormatter = formatter("MMMM yyyy")

    /// The ISO day a date picker's value falls on, read in UTC to match `date(_:)`.
    static func iso(_ date: Date) -> String {
        DateUtils.isoString(date, timeZone: utc)
    }

    static let utc = TimeZone(identifier: "UTC")!

    static func weekday(_ iso: String) -> String { weekdayFormatter.string(from: date(iso)) }
    static func shortDay(_ iso: String) -> String { shortDayFormatter.string(from: date(iso)) }
    static func mediumDay(_ iso: String) -> String { mediumDayFormatter.string(from: date(iso)) }
    static func longDay(_ iso: String) -> String { longDayFormatter.string(from: date(iso)) }
    static func monthTitle(_ iso: String) -> String { monthFormatter.string(from: date(iso)) }

    /// A bag's age in days since roast at its first and last cup: "day 18–32".
    static func ages(_ range: AgeRange) -> String {
        range.start == range.finish ? "day \(range.start)" : "day \(range.start)–\(range.finish)"
    }

    /// 0 = Monday ... 6 = Sunday. 1970-01-01 was a Thursday.
    static func weekdayIndex(_ iso: String) -> Int {
        ((DateUtils.dayNumber(iso) ?? 0) + 3) % 7
    }

    static func weekTitle(_ monday: String, today: String) -> String {
        let thisWeek = DateUtils.addDays(today, -weekdayIndex(today))
        switch DateUtils.daysBetween(thisWeek, monday) {
        case 0: return "This week"
        case 7: return "Next week"
        default: return "Week of \(shortDay(monday))"
        }
    }

    static func grams(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
