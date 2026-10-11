import AppIntents
import CoffeeCore
import Foundation
import WidgetKit

/// Which month the widget shows. The arrows move it; it goes back to the
/// current month the next day.
enum ShownMonth {
    private static let monthKey = "widgetMonth"
    private static let dayKey = "widgetMonthSetOn"
    /// As far as the schedule the app hands over reaches: two months back, four on.
    private static let monthsBack = 2
    private static let monthsAhead = 4

    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.appGroup) }

    /// First of the month to draw.
    static func current(today: String) -> String {
        guard let month = defaults?.string(forKey: monthKey), defaults?.string(forKey: dayKey) == today
        else { return DateUtils.firstOfMonth(today) }
        return month
    }

    static func canMove(_ months: Int, today: String) -> Bool {
        let thisMonth = DateUtils.firstOfMonth(today)
        let target = DateUtils.addMonths(current(today: today), months)
        return target >= DateUtils.addMonths(thisMonth, -monthsBack) && target <= DateUtils.addMonths(thisMonth, monthsAhead)
    }

    /// Move by a number of months, or with 0 back to the current month.
    static func move(_ months: Int, today: String) {
        guard months == 0 || canMove(months, today: today) else { return }
        let target = months == 0 ? DateUtils.firstOfMonth(today) : DateUtils.addMonths(current(today: today), months)
        defaults?.set(target, forKey: monthKey)
        defaults?.set(today, forKey: dayKey)
    }
}

/// The widget's arrows: show the month before or after. WidgetKit redraws
/// the widget once it has run.
struct ShiftMonthIntent: AppIntent {
    static let title: LocalizedStringResource = "Change the month shown"
    static let isDiscoverable = false

    /// -1 or 1; 0 goes back to the current month.
    @Parameter(title: "Months")
    var months: Int

    init() {}

    init(months: Int) {
        self.months = months
    }

    func perform() async throws -> some IntentResult {
        ShownMonth.move(months, today: DateUtils.today())
        return .result()
    }
}
