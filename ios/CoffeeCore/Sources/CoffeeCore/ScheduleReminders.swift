/// Something the schedule says to do on a day, for the app to send as a
/// notification that morning.
public struct Reminder: Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        /// A frozen bag's planned thaw date: take it out of the freezer.
        case thaw
        /// An unopened bag's first day.
        case newBag
        /// The last day a bag can be bought and still have rested in time.
        case buy
    }

    public var kind: Kind
    /// The ISO day it's sent on.
    public var date: String
    /// The bag it's about, or empty.
    public var beanID: String
    public var title: String
    public var body: String

    /// The same for the same event, so scheduling it again replaces it.
    /// It starts with the date, which the app reads back.
    public var id: String { "\(date)|\(kind.rawValue)|\(beanID)" }
}

public enum ScheduleReminders {
    /// The reminders for the days after `today`, earliest first. Today's
    /// aren't planned: by the time the app is open they have been sent.
    public static func plan(schedule: [ScheduleDay], beans: [Bean], runway: Runway?, today: String) -> [Reminder] {
        let starts = Scheduler.startDates(schedule)
        var reminders: [Reminder] = []
        for bean in beans where !bean.archived {
            if bean.isFrozen {
                if let thaw = bean.plannedThawDate, thaw > today { reminders.append(self.thaw(bean, on: thaw)) }
            } else if let start = starts[bean.id], start > today, bean.totalBrewedGrams == 0 {
                let cup = schedule.first { $0.date == start }?.consumptions.first { $0.beanID == bean.id }
                reminders.append(newBag(bean, on: start, daysEarly: cup?.daysEarly ?? 0))
            }
        }
        if let runway, runway.buyBy > today { reminders.append(buy(runway)) }
        return reminders.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    private static func thaw(_ bean: Bean, on date: String) -> Reminder {
        Reminder(
            kind: .thaw, date: date, beanID: bean.id,
            title: "Thaw \(bean.name)",
            body: "It comes out of the freezer today and is back in the schedule."
        )
    }

    private static func newBag(_ bean: Bean, on date: String, daysEarly: Int) -> Reminder {
        var body = bean.roaster.isEmpty ? "\(bean.name) starts today." : "\(bean.name) from \(bean.roaster) starts today."
        if daysEarly > 0 {
            body += " That's \(days(daysEarly)) before it has finished resting."
        }
        return Reminder(kind: .newBag, date: date, beanID: bean.id, title: "New bag today", body: body)
    }

    private static func buy(_ runway: Runway) -> Reminder {
        // From the buy-by day to the first day without coffee is the rest a new bag needs
        let rest = DateUtils.daysBetween(runway.buyBy, runway.runsOut)
        return Reminder(
            kind: .buy, date: runway.buyBy, beanID: "",
            title: "Buy coffee today",
            body: "The coffee runs out in \(days(rest)), which is how long a new bag rests."
        )
    }

    private static func days(_ count: Int) -> String { "\(count) \(count == 1 ? "day" : "days")" }
}
