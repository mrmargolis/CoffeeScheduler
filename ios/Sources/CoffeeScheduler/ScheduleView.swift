import CoffeeCore
import SwiftUI

/// Upcoming days, a week per section, starting with the current week.
struct ScheduleView: View {
    @Environment(AppModel.self) private var model
    @State private var pickingFolder = false
    @State private var path: [BeanRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !model.hasFolder {
                    Section {
                        FolderPrompt { pickingFolder = true }
                    }
                }
                ForEach(weeks, id: \.first?.date) { week in
                    Section(Format.weekTitle(week.first!.date, today: model.today)) {
                        ForEach(week) { day in
                            DayRow(day: day, isToday: day.date == model.today) { id in
                                path.append(BeanRoute(id: id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Schedule")
            .navigationDestination(for: BeanRoute.self) { BeanDetailView(beanID: $0.id) }
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

    /// Days from the start of this week (Monday) onward, chunked by week.
    private var weeks: [[ScheduleDay]] {
        let weekday = Format.weekdayIndex(model.today) // 0 = Monday
        let start = DateUtils.addDays(model.today, -weekday)
        let upcoming = model.schedule.filter { $0.date >= start }
        return stride(from: 0, to: upcoming.count, by: 7).map {
            Array(upcoming[$0..<min($0 + 7, upcoming.count)])
        }
    }
}

private struct DayRow: View {
    let day: ScheduleDay
    let isToday: Bool
    let openBean: (String) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text(Format.weekday(day.date)).font(.subheadline.weight(isToday ? .bold : .regular))
                Text(Format.shortDay(day.date)).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                if day.isSkip {
                    Text("Skip").foregroundStyle(.secondary)
                } else if day.isGap {
                    Label(day.isActual ? "No brews logged" : "No coffee", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(day.isActual ? Color.secondary : Color.red)
                }
                ForEach(day.consumptions, id: \.beanID) { c in
                    // One button per bag: a day can hold two, and a row-wide
                    // link couldn't tell them apart.
                    Button { openBean(c.beanID) } label: {
                        HStack {
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

    /// The ISO day a date picker's value falls on, read in UTC to match `date(_:)`.
    static func iso(_ date: Date) -> String {
        DateUtils.isoString(date, timeZone: utc)
    }

    static let utc = TimeZone(identifier: "UTC")!

    static func weekday(_ iso: String) -> String { weekdayFormatter.string(from: date(iso)) }
    static func shortDay(_ iso: String) -> String { shortDayFormatter.string(from: date(iso)) }
    static func mediumDay(_ iso: String) -> String { mediumDayFormatter.string(from: date(iso)) }

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
