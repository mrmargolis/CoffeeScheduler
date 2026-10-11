/// The one-line answer to "am I fine?" at the top of the schedule: how long
/// the coffee lasts, what's on the grinder, and the one thing most worth a
/// look. Port of `src/components/RunwayStrip.tsx` with `summarizeSchedule`
/// (`src/lib/calendar-utils.ts`) and `extractBeanEarlyStarts`
/// (`src/lib/schedule-utils.ts`).
public struct RunwaySummary: Hashable, Sendable {
    public enum Attention: Hashable, Sendable {
        /// No coffee scheduled from this date.
        case gap(date: String)
        /// The bag started the most days before it's rested.
        case earlyStart(bean: Bean, days: Int, startDate: String?)
    }

    /// Projected days from today on that have coffee (not gaps or skips).
    public var daysOfCoffee: Int
    /// First projected day with no coffee.
    public var nextGapDate: String?
    /// The bag in progress: partly used, not frozen.
    public var brewing: Bean?
    /// A coming gap outranks an early start.
    public var attention: Attention?

    /// - Parameter beans: unarchived beans in queue order (the first bag in
    ///   progress is the one shown as brewing).
    public init(schedule: [ScheduleDay], beans: [Bean], today: String) {
        let future = schedule.filter { $0.date >= today && !$0.isActual }
        daysOfCoffee = future.filter { !$0.isGap && !$0.isSkip }.count
        nextGapDate = future.first(where: \.isGap)?.date
        brewing = beans.first { !$0.isFrozen && $0.remainingGrams > 0 && $0.remainingGrams < $0.weightGrams }

        if let nextGapDate {
            attention = .gap(date: nextGapDate)
            return
        }
        // Most days early wins; on a tie, the one scheduled first.
        var worst: (id: String, days: Int)?
        for (id, days) in Scheduler.earlyStarts(schedule) where days > (worst?.days ?? 0) {
            worst = (id, days)
        }
        if let worst, let bean = beans.first(where: { $0.id == worst.id }) {
            attention = .earlyStart(bean: bean, days: worst.days, startDate: Scheduler.startDates(schedule)[bean.id])
        }
    }
}

extension Scheduler {
    /// For each bean started before its ready date, how many days early its
    /// first scheduled day is, in schedule order. Beans that start on or after
    /// their ready date are left out. Port of `extractBeanEarlyStarts`.
    public static func earlyStarts(_ schedule: [ScheduleDay]) -> [(beanID: String, days: Int)] {
        var seen = Set<String>()
        var result: [(beanID: String, days: Int)] = []
        for day in schedule {
            for c in day.consumptions where seen.insert(c.beanID).inserted {
                if let early = c.daysEarly, early > 0 { result.append((c.beanID, early)) }
            }
        }
        return result
    }
}
