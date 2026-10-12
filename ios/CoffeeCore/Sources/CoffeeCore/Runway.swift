/// How long the coffee lasts, and when the next bag has to be bought for it
/// to have rested by then. A bag is taken to be roasted the day it's bought.
public struct Runway: Hashable, Sendable {
    /// The last day with coffee before `runsOut`; nil when there is none from today on.
    public let lastCoffeeDay: String?
    /// The first day from today on with nothing to drink.
    public let runsOut: String
    /// A bag bought on this day has rested by `runsOut`. In the past once it's too late.
    public let buyBy: String
    /// The day a bag bought today has rested.
    public let restedIfBoughtToday: String
    /// Days without coffee before a bag bought today has rested; 0 while there is still time.
    public let daysShort: Int
}

extension Scheduler {
    /// The runway from `today`, for a next bag that rests `restDays`. Nil
    /// when the schedule has coffee on every day it covers; skipped days
    /// don't count as running out.
    public static func runway(_ schedule: [ScheduleDay], restDays: Int, today: String) -> Runway? {
        let upcoming = schedule.filter { $0.date >= today }
        guard let gap = upcoming.first(where: { $0.isGap && !$0.isActual }) else { return nil }
        let rested = DateUtils.addDays(today, restDays)
        return Runway(
            lastCoffeeDay: upcoming.last { $0.date < gap.date && !$0.consumptions.isEmpty }?.date,
            runsOut: gap.date,
            buyBy: DateUtils.addDays(gap.date, -restDays),
            restedIfBoughtToday: rested,
            daysShort: max(0, DateUtils.daysBetween(gap.date, rested))
        )
    }
}
