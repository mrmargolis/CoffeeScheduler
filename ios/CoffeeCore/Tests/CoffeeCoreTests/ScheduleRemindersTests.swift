import Testing

@testable import CoffeeCore

@Suite struct ScheduleRemindersTests {
    let store: CoffeeStore
    let today = "2026-03-01"

    init() throws {
        store = try CoffeeStore.inMemory()
    }

    /// A 250 g bag, rested by `today` unless a later roast date says otherwise.
    func insertBag(_ id: String, roast: String = "2026-01-01", frozen: Bool = false, thaw: String? = nil) throws {
        try store.db.run(
            """
            INSERT INTO beans (id, name, roaster, roast_date, weight_grams, is_frozen, planned_thaw_date)
            VALUES (?, ?, 'Roaster', ?, 250, ?, ?)
            """,
            [.text(id), .text("Bag \(id)"), .text(roast), SQLValue(frozen), SQLValue(thaw)]
        )
    }

    func brew(_ id: String, on date: String) throws {
        try store.db.run("INSERT INTO brews (bean_id, ground_coffee_grams, creation_date) VALUES (?, 45, ?)", [.text(id), .text(date)])
    }

    func plan(restDays: Int = 3) throws -> [Reminder] {
        let schedule = try store.schedule(start: "2026-02-01", end: "2026-04-30", today: today)
        return ScheduleReminders.plan(
            schedule: schedule,
            beans: try store.beans(archived: false, today: today),
            runway: Scheduler.runway(schedule, restDays: restDays, today: today),
            today: today
        )
    }

    @Test func aPlannedThawIsRemindedOnItsDay() throws {
        try insertBag("a", frozen: true, thaw: "2026-03-10")
        let thaw = try #require(try plan().first { $0.kind == .thaw })
        #expect(thaw.date == "2026-03-10")
        #expect(thaw.title == "Thaw Bag a")
        #expect(thaw.id == "2026-03-10|thaw|a")
    }

    @Test func aFrozenBagWithNoThawDateHasNoReminder() throws {
        try insertBag("a", frozen: true)
        #expect(try plan().isEmpty)
    }

    @Test func anUnopenedBagIsRemindedOnItsFirstDay() throws {
        try insertBag("a")
        try brew("a", on: "2026-02-28")
        try insertBag("b", roast: "2026-01-02")
        // Bag a has 205 g: four days at 45 g, then a last 15 g on the fifth, shared with b
        let reminders = try plan().filter { $0.kind == .newBag }
        #expect(reminders.map(\.date) == ["2026-03-05"])
        #expect(reminders.first?.body == "Bag b from Roaster starts today.")
    }

    @Test func aBagStartingBeforeItHasRestedSaysSo() throws {
        try insertBag("a")
        try brew("a", on: "2026-02-28")
        try insertBag("b", roast: "2026-02-08")  // rested on March 10
        let reminder = try #require(try plan().first { $0.kind == .newBag })
        #expect(reminder.body == "Bag b from Roaster starts today. That's 5 days before it has finished resting.")
    }

    @Test func theBagOnTheGrinderHasNoReminder() throws {
        try insertBag("a")
        try brew("a", on: "2026-02-28")
        #expect(try plan().filter { $0.kind == .newBag }.isEmpty)
    }

    @Test func buyingIsRemindedOnTheLastDayThatWorks() throws {
        try insertBag("a")
        // 250 g lasts through March 6, so nothing from the 7th
        let buy = try #require(try plan(restDays: 3).first { $0.kind == .buy })
        #expect(buy.date == "2026-03-04")
        #expect(buy.body == "The coffee runs out in 3 days, which is how long a new bag rests.")
    }

    @Test func noBuyReminderOnceItIsTooLate() throws {
        try insertBag("a")
        #expect(try plan(restDays: 30).filter { $0.kind == .buy }.isEmpty)
    }

    @Test func nothingIsPlannedForToday() throws {
        try insertBag("a")  // unopened, and it starts today
        try insertBag("b", frozen: true, thaw: today)
        // Buying is still ahead; the bags' own reminders were for this morning
        #expect(try plan().map(\.kind) == [.buy])
    }

    @Test func earliestFirst() throws {
        try insertBag("a")
        try brew("a", on: "2026-02-28")
        try insertBag("b", roast: "2026-01-02")
        try insertBag("c", frozen: true, thaw: "2026-03-03")
        let dates = try plan().map(\.date)
        #expect(dates == dates.sorted())
        #expect(dates.count == 3)
    }
}
