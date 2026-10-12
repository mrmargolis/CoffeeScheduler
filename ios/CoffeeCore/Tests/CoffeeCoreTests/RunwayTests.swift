import Testing

@testable import CoffeeCore

/// One rested 250 g bag at 45 g a day from March 1: five full days, a last
/// 15 g dose on the 6th, and nothing from the 7th.
@Suite struct RunwayTests {
    let today = "2026-03-01"

    func days(to end: String = "2026-04-30", beans: [Scheduler.Bean] = [makeBean()], skipDays: Set<String> = []) -> [ScheduleDay] {
        schedule("2026-02-20", end, beans: beans, today: today, skipDays: skipDays)
    }

    @Test func runsOutOnTheFirstDayWithNothingToDrink() throws {
        let runway = try #require(Scheduler.runway(days(), restDays: 3, today: today))
        #expect(runway.lastCoffeeDay == "2026-03-06")
        #expect(runway.runsOut == "2026-03-07")
    }

    @Test func buyByLeavesTimeToRest() throws {
        let runway = try #require(Scheduler.runway(days(), restDays: 3, today: today))
        #expect(runway.buyBy == "2026-03-04")
        #expect(runway.daysShort == 0)
    }

    @Test func buyingOnTheLastDayThatWorksIsNotShort() throws {
        let runway = try #require(Scheduler.runway(days(), restDays: 6, today: today))
        #expect(runway.buyBy == today)
        #expect(runway.restedIfBoughtToday == "2026-03-07")
        #expect(runway.daysShort == 0)
    }

    @Test func tooLateCountsTheDaysWithoutCoffee() throws {
        let runway = try #require(Scheduler.runway(days(), restDays: 30, today: today))
        #expect(runway.buyBy == "2026-02-05")
        #expect(runway.restedIfBoughtToday == "2026-03-31")
        #expect(runway.daysShort == 24)
    }

    @Test func nilWhileTheScheduleHasCoffeeThroughout() {
        #expect(Scheduler.runway(days(to: "2026-03-05"), restDays: 30, today: today) == nil)
    }

    @Test func skippedDaysAreNotRunningOut() throws {
        let runway = try #require(Scheduler.runway(days(skipDays: ["2026-03-03", "2026-03-08"]), restDays: 3, today: today))
        #expect(runway.lastCoffeeDay == "2026-03-07")
        #expect(runway.runsOut == "2026-03-09")
    }

    @Test func pastDaysWithNoBrewsAreNotRunningOut() throws {
        // February has no brews logged, which the schedule marks as gaps too
        let runway = try #require(Scheduler.runway(days(), restDays: 3, today: today))
        #expect(runway.runsOut > today)
    }

    @Test func nothingToDrinkTodayHasNoLastDay() throws {
        let runway = try #require(Scheduler.runway(days(beans: []), restDays: 3, today: today))
        #expect(runway.lastCoffeeDay == nil)
        #expect(runway.runsOut == today)
    }
}
