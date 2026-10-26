import Testing

@testable import CoffeeCore

@Suite struct BacklogSummaryTests {
    private func bean(weight: Double, brewed: Double = 0, frozen: Bool = false) -> Bean {
        var bean = makeDetailBean(weightGrams: weight, totalBrewedGrams: brewed)
        bean.isFrozen = frozen
        return bean
    }

    @Test func countsQueuedAndFrozenBagsAndAllTheCoffeeLeft() {
        let beans = [bean(weight: 250, brewed: 100), bean(weight: 250), bean(weight: 100, frozen: true)]
        let summary = BacklogSummary(beans: beans, lastCoffeeDay: "2026-11-30", today: "2026-10-21")
        #expect(summary.queuedBags == 2)
        #expect(summary.frozenBags == 1)
        #expect(summary.grams == 500)
    }

    @Test func countsTodayAndTheLastDayInTheDaysOfCoffee() {
        let summary = BacklogSummary(beans: [bean(weight: 250)], lastCoffeeDay: "2026-10-30", today: "2026-10-21")
        #expect(summary.coffeeDays == 10)
        #expect(BacklogSummary(beans: [], lastCoffeeDay: "2026-10-21", today: "2026-10-21").coffeeDays == 1)
    }

    @Test func hasNoDaysOfCoffeeWithNoneReady() {
        #expect(BacklogSummary(beans: [bean(weight: 250)], lastCoffeeDay: nil, today: "2026-10-21").coffeeDays == nil)
        #expect(BacklogSummary(beans: [], lastCoffeeDay: "2026-10-20", today: "2026-10-21").coffeeDays == nil)
    }

    @Test func doesntCountABagBrewedPastItsWeight() {
        #expect(BacklogSummary(beans: [bean(weight: 250, brewed: 260)], lastCoffeeDay: nil, today: "2026-10-21").grams == 0)
    }
}
