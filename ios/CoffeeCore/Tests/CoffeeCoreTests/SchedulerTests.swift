import Testing

@testable import CoffeeCore

// Ported from src/__tests__/lib/scheduler.test.ts.

func makeBean(
    id: String = "bean-1",
    name: String = "Test Bean",
    roastDate: String? = "2026-01-01",
    weightGrams: Double = 250,
    remainingGrams: Double = 250,
    effectiveRestDays: Int = 30,
    isFrozen: Bool = false,
    plannedThawDate: String? = nil,
    freezeAfterGrams: Double? = nil,
    displayOrder: Int? = nil,
    frozenDays: Int = 0
) -> Scheduler.Bean {
    Scheduler.Bean(
        id: id, name: name, roaster: "Test Roaster", roastDate: roastDate,
        weightGrams: weightGrams, remainingGrams: remainingGrams,
        effectiveRestDays: effectiveRestDays, isFrozen: isFrozen,
        plannedThawDate: plannedThawDate, freezeAfterGrams: freezeAfterGrams,
        displayOrder: displayOrder, frozenDays: frozenDays
    )
}

func schedule(
    _ start: String, _ end: String,
    beans: [Scheduler.Bean],
    brews: [Scheduler.Brew] = [],
    today: String = "2026-01-01",
    daily: Double = 45,
    skipDays: Set<String> = [],
    overrides: [String: Scheduler.DayOverride] = [:]
) -> [ScheduleDay] {
    Scheduler.computeSchedule(
        startDate: start, endDate: end, dailyConsumptionGrams: daily,
        beans: beans, actualBrews: brews, today: today,
        skipDays: skipDays, consumptionOverrides: overrides
    )
}

@Suite struct ReadyDateTests {
    @Test func roastPlusRest() {
        #expect(Scheduler.readyDate(makeBean()) == "2026-01-31")
    }

    @Test func accountsForFrozenDays() {
        #expect(Scheduler.readyDate(makeBean(frozenDays: 10)) == "2026-02-10")
    }

    @Test func nilWithoutRoastDate() {
        #expect(Scheduler.readyDate(makeBean(roastDate: nil)) == nil)
    }
}

@Suite struct SortQueueTests {
    @Test func displayOrderFirst() {
        let sorted = Scheduler.sortQueue([
            makeBean(id: "b1", displayOrder: 3),
            makeBean(id: "b2", displayOrder: 1),
            makeBean(id: "b3"),
        ])
        #expect(sorted.map(\.id) == ["b2", "b1", "b3"])
    }

    @Test func unorderedByReadyDate() {
        let sorted = Scheduler.sortQueue([
            makeBean(id: "b1", roastDate: "2026-02-01"),
            makeBean(id: "b2", roastDate: "2026-01-01"),
        ])
        #expect(sorted.first?.id == "b2")
    }

    @Test func inProgressBeforeUntouched() {
        let sorted = Scheduler.sortQueue([
            makeBean(id: "untouched", weightGrams: 200, remainingGrams: 200),
            makeBean(id: "in-progress", roastDate: "2026-01-10", weightGrams: 200, remainingGrams: 50),
        ])
        #expect(sorted.map(\.id) == ["in-progress", "untouched"])
    }

    @Test func noReadyDateLast() {
        let sorted = Scheduler.sortQueue([
            makeBean(id: "b1", roastDate: nil),
            makeBean(id: "b2"),
        ])
        #expect(sorted.map(\.id) == ["b2", "b1"])
    }
}

@Suite struct ComputeScheduleTests {
    @Test func consumesSingleBag() {
        let days = schedule("2026-01-31", "2026-02-02", beans: [makeBean(remainingGrams: 90)])
        #expect(days.count == 3)
        #expect(days[0].consumptions.first?.grams == 45)
        #expect(days[0].isGap == false)
        #expect(days[1].consumptions.first?.grams == 45)
        #expect(days[2].isGap)
        #expect(days[2].consumptions.isEmpty)
    }

    @Test func transitionsBetweenBags() {
        let days = schedule(
            "2026-01-31", "2026-01-31",
            beans: [
                makeBean(id: "b1", name: "Bean 1", weightGrams: 200, remainingGrams: 30),
                makeBean(id: "b2", name: "Bean 2"),
            ])
        #expect(
            days[0].consumptions == [
                Consumption(beanID: "b1", beanName: "Bean 1", roaster: "Test Roaster", grams: 30),
                Consumption(beanID: "b2", beanName: "Bean 2", roaster: "Test Roaster", grams: 15),
            ])
    }

    @Test func roundsPartialBagToDoses() {
        let days = schedule(
            "2026-01-31", "2026-01-31",
            beans: [
                makeBean(id: "b1", weightGrams: 200, remainingGrams: 40),
                makeBean(id: "b2"),
            ])
        #expect(days[0].consumptions.map(\.beanID) == ["b1", "b2"])
        #expect(days[0].consumptions.map(\.grams) == [30, 15])
    }

    @Test func singleBagFillsLargerTarget() {
        let days = schedule(
            "2026-01-31", "2026-01-31",
            beans: [
                makeBean(id: "b1"), makeBean(id: "b2"),
            ], daily: 50)
        #expect(days[0].consumptions.map(\.beanID) == ["b1"])
        #expect(days[0].consumptions.first?.grams == 50)
    }

    @Test func respectsDisplayOrder() {
        let days = schedule(
            "2026-01-31", "2026-01-31",
            beans: [
                makeBean(id: "b1", displayOrder: 2),
                makeBean(id: "b2", displayOrder: 1),
            ])
        #expect(days[0].consumptions.first?.beanID == "b2")
    }

    @Test func startsUnrestedBeanEarly() {
        let days = schedule("2026-02-13", "2026-02-15", beans: [makeBean(roastDate: "2026-01-15")])
        #expect(days[0].isGap == false)
        #expect(days[0].consumptions.first?.daysEarly == 1)
        #expect(days[1].consumptions.first?.daysEarly == nil)
        #expect(days[2].isGap == false)
    }

    @Test func detectsSurplus() {
        let days = schedule("2026-01-31", "2026-01-31", beans: [makeBean(id: "b1"), makeBean(id: "b2")])
        #expect(days[0].isSurplus)
    }

    @Test func frozenDaysShiftReadyDate() {
        let days = schedule("2026-02-14", "2026-02-16", beans: [makeBean(frozenDays: 15)])
        #expect(days[0].consumptions.first?.daysEarly == 1)
        #expect(days[1].consumptions.first?.daysEarly == nil)
    }

    @Test func pastDaysUseActualBrews() {
        let brew = Scheduler.Brew(beanID: "b1", creationDate: "2026-02-01", groundCoffeeGrams: 15)
        let days = schedule(
            "2026-02-01", "2026-02-03", beans: [makeBean(id: "b1")],
            brews: [brew, brew], today: "2026-02-02")
        #expect(days[0].isActual)
        #expect(days[0].consumptions.count == 1)
        #expect(days[0].consumptions.first?.grams == 30)
        #expect(days[1].isActual == false)
        #expect(days[1].consumptions.first?.grams == 45)
    }

    @Test func pastDaysWithoutBrewsAreGaps() {
        let days = schedule("2026-02-01", "2026-02-01", beans: [makeBean()], today: "2026-02-15")
        #expect(days[0].isActual)
        #expect(days[0].isGap)
    }

    @Test func skipDaysConsumeNothing() {
        let days = schedule(
            "2026-01-31", "2026-02-01", beans: [makeBean(remainingGrams: 45)],
            skipDays: ["2026-01-31"])
        #expect(days[0].isSkip)
        #expect(days[0].consumptions.isEmpty)
        #expect(days[1].consumptions.first?.grams == 45)
    }

    @Test func frozenBeanWithoutThawIsExcluded() {
        let days = schedule("2026-01-31", "2026-01-31", beans: [makeBean(isFrozen: true)])
        #expect(days[0].isGap)
    }

    @Test func frozenBeanWaitsForPlannedThaw() {
        let days = schedule(
            "2026-01-31", "2026-02-02",
            beans: [
                makeBean(isFrozen: true, plannedThawDate: "2026-02-02")
            ])
        #expect(days[0].isGap)
        #expect(days[2].consumptions.first?.grams == 45)
    }

    @Test func freezeAfterGramsCapsConsumption() {
        // 250g bag, freeze after 100g: only 100g can be scheduled
        let days = schedule("2026-01-31", "2026-02-03", beans: [makeBean(freezeAfterGrams: 100)])
        let total = days.flatMap(\.consumptions).reduce(0) { $0 + $1.grams }
        #expect(total == 90)
    }

    @Test func consumptionOverride() {
        let days = schedule(
            "2026-01-31", "2026-01-31", beans: [makeBean()],
            overrides: ["2026-01-31": .init(dailyGrams: 30, doseSize: 15)])
        #expect(days[0].consumptions.first?.grams == 30)
    }

    @Test func mergesPreLoggedFutureBrew() {
        let brew = Scheduler.Brew(beanID: "bean-1", creationDate: "2026-02-01", groundCoffeeGrams: 15)
        let days = schedule("2026-02-01", "2026-02-01", beans: [makeBean()], brews: [brew], today: "2026-01-31")
        #expect(days[0].consumptions.count == 1)
        #expect(days[0].consumptions.first?.grams == 45)
    }
}
