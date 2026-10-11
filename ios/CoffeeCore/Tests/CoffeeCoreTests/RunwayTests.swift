import Testing
@testable import CoffeeCore

// Ported from summarizeSchedule in src/__tests__/lib/calendar-utils.test.ts,
// extractBeanEarlyStarts in schedule-utils.test.ts, and RunwayStrip's rules.

private func projected(
    _ date: String, _ uses: [(String, Int?)] = [], gap: Bool = false, skip: Bool = false, actual: Bool = false
) -> ScheduleDay {
    ScheduleDay(
        date: date,
        consumptions: uses.map { Consumption(beanID: $0.0, beanName: $0.0, roaster: "R", grams: 45, daysEarly: $0.1) },
        isGap: gap, isSurplus: false, isActual: actual, isSkip: skip
    )
}

private func bean(_ id: String, brewed: Double = 0, frozen: Bool = false) -> Bean {
    var bean = makeDetailBean(totalBrewedGrams: brewed)
    bean.id = id
    bean.name = id
    bean.isFrozen = frozen
    return bean
}

@Suite struct RunwayTests {
    @Test func countsDaysOfCoffeeAndFindsTheNextGap() {
        let schedule = [
            projected("2026-03-01", [("b1", nil)]),
            projected("2026-03-02", [("b1", nil)]),
            projected("2026-03-03", gap: true),
            projected("2026-03-04", skip: true),
        ]
        let summary = RunwaySummary(schedule: schedule, beans: [], today: "2026-03-01")
        #expect(summary.daysOfCoffee == 2)
        #expect(summary.nextGapDate == "2026-03-03")
        #expect(summary.attention == .gap(date: "2026-03-03"))
    }

    @Test func emptySchedule() {
        let summary = RunwaySummary(schedule: [], beans: [], today: "2026-03-01")
        #expect(summary.daysOfCoffee == 0)
        #expect(summary.nextGapDate == nil)
        #expect(summary.brewing == nil)
        #expect(summary.attention == nil)
    }

    @Test func ignoresPastAndActualDays() {
        let schedule = [
            projected("2026-02-28", gap: true),
            projected("2026-03-01", gap: true, actual: true),
            projected("2026-03-02", [("b1", nil)]),
        ]
        let summary = RunwaySummary(schedule: schedule, beans: [], today: "2026-03-01")
        #expect(summary.daysOfCoffee == 1)
        #expect(summary.nextGapDate == nil)
    }

    @Test func brewingIsTheFirstPartlyUsedBagThatIsNotFrozen() {
        let beans = [
            bean("untouched"),
            bean("frozen", brewed: 100, frozen: true),
            bean("open", brewed: 100),
            bean("also-open", brewed: 50),
            bean("empty", brewed: 250),
        ]
        #expect(RunwaySummary(schedule: [], beans: beans, today: "2026-03-01").brewing?.id == "open")
    }

    @Test func flagsTheBagStartedMostDaysEarly() {
        let schedule = [
            projected("2026-03-01", [("a", 2)]),
            projected("2026-03-02", [("a", 1), ("b", 5)]),
            projected("2026-03-03", [("c", 5)]),
        ]
        let summary = RunwaySummary(schedule: schedule, beans: [bean("a"), bean("b"), bean("c")], today: "2026-03-01")
        // b and c tie at 5; b is scheduled first
        #expect(summary.attention == .earlyStart(bean: bean("b"), days: 5, startDate: "2026-03-02"))
    }

    @Test func aGapOutranksAnEarlyStart() {
        let schedule = [
            projected("2026-03-01", [("a", 4)]),
            projected("2026-03-02", gap: true),
        ]
        let summary = RunwaySummary(schedule: schedule, beans: [bean("a")], today: "2026-03-01")
        #expect(summary.attention == .gap(date: "2026-03-02"))
    }

    @Test func nothingToFlagWhenEveryBagStartsRested() {
        let schedule = [projected("2026-03-01", [("a", nil)])]
        #expect(RunwaySummary(schedule: schedule, beans: [bean("a")], today: "2026-03-01").attention == nil)
    }

    // extractBeanEarlyStarts

    @Test func earlyStartsComeFromTheFirstScheduledDay() {
        let schedule = [
            projected("2025-01-01", [("a", 3)]),
            projected("2025-01-02", [("a", 2)]),
            projected("2025-01-03", [("a", 1)]),
        ]
        #expect(Scheduler.earlyStarts(schedule).map(\.days) == [3])
    }

    @Test func earlinessOnLaterDaysIsIgnored() {
        let schedule = [
            projected("2025-01-01", [("a", nil)]),
            projected("2025-01-02", [("a", 5)]),
        ]
        #expect(Scheduler.earlyStarts(schedule).isEmpty)
    }

    @Test func onlyEarlyBagsAreListed() {
        let schedule = [projected("2025-01-01", [("a", nil), ("b", 2)])]
        let early = Scheduler.earlyStarts(schedule)
        #expect(early.map(\.beanID) == ["b"])
        #expect(early.map(\.days) == [2])
    }

    @Test func noEarlyStartsInAnEmptySchedule() {
        #expect(Scheduler.earlyStarts([]).isEmpty)
    }
}
