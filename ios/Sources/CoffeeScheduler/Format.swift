import CoffeeCore
import Foundation

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

    /// The day of the month: "7".
    static func dayNumber(_ iso: String) -> String { String(Int(iso.suffix(2)) ?? 0) }

    /// "Oct 12 – Oct 18", or the one day when both ends are the same.
    static func span(_ start: String, _ end: String) -> String {
        start == end ? shortDay(start) : "\(shortDay(start)) – \(shortDay(end))"
    }

    /// "3 days", "1 day".
    static func days(_ count: Int) -> String { "\(count) \(count == 1 ? "day" : "days")" }

    /// "today", "yesterday", "3 days ago".
    static func daysAgo(_ iso: String, today: String) -> String {
        switch DateUtils.daysBetween(iso, today) {
        case ...0: "today"
        case 1: "yesterday"
        case let count: "\(count) days ago"
        }
    }

    /// A bag's age in days since roast at its first and last cup: "day 18–32".
    static func ages(_ range: AgeRange) -> String {
        range.start == range.finish ? "day \(range.start)" : "day \(range.start)–\(range.finish)"
    }

    /// 0 = Monday ... 6 = Sunday.
    static func weekdayIndex(_ iso: String) -> Int {
        MonthGrid.weekdayIndex(iso)
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
