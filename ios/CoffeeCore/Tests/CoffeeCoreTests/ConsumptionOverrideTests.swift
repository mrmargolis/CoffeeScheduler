import Testing

@testable import CoffeeCore

// The web app has no tests for /api/consumption-overrides; these cover the
// store methods and that the schedule applies what they save.
@Suite struct ConsumptionOverrideTests {
    let store: CoffeeStore

    init() throws {
        store = try CoffeeStore.inMemory()
    }

    func overrides() throws -> [ConsumptionOverride] {
        try store.consumptionOverrides(from: "0000-01-01")
    }

    @Test func setsAOneDayOverride() throws {
        try store.setConsumptionOverride(date: "2026-03-10", dailyGrams: 60, doseSizeGrams: 20)
        let saved = try overrides()
        #expect(saved.count == 1)
        #expect(saved.first?.startDate == "2026-03-10")
        #expect(saved.first?.endDate == "2026-03-10")
        #expect(saved.first?.dailyGrams == 60)
        #expect(saved.first?.doseSizeGrams == 20)
    }

    @Test func settingAgainReplacesTheDaysOverride() throws {
        try store.setConsumptionOverride(date: "2026-03-10", dailyGrams: 60, doseSizeGrams: 20)
        try store.setConsumptionOverride(date: "2026-03-10", dailyGrams: 30, doseSizeGrams: 15)
        #expect(try overrides().map(\.dailyGrams) == [30])
    }

    @Test func otherDaysAreLeftAlone() throws {
        try store.setConsumptionOverride(date: "2026-03-10", dailyGrams: 60, doseSizeGrams: 20)
        try store.setConsumptionOverride(date: "2026-03-11", dailyGrams: 30, doseSizeGrams: 15)
        #expect(try overrides().map(\.startDate) == ["2026-03-10", "2026-03-11"])
    }

    @Test func rejectsZeroOrNegativeAmounts() throws {
        #expect(throws: ConsumptionOverrideError.notPositive) {
            try store.setConsumptionOverride(date: "2026-03-10", dailyGrams: 0, doseSizeGrams: 15)
        }
        #expect(throws: ConsumptionOverrideError.notPositive) {
            try store.setConsumptionOverride(date: "2026-03-10", dailyGrams: 45, doseSizeGrams: -1)
        }
        #expect(try overrides().isEmpty)
    }

    @Test func deleteRemovesIt() throws {
        try store.setConsumptionOverride(date: "2026-03-10", dailyGrams: 60, doseSizeGrams: 20)
        try store.deleteConsumptionOverride(id: try #require(overrides().first).id)
        #expect(try overrides().isEmpty)
    }

    @Test func listingLeavesOutOverridesThatAlreadyEnded() throws {
        try store.setConsumptionOverride(date: "2026-03-01", dailyGrams: 60, doseSizeGrams: 20)
        try store.setConsumptionOverride(date: "2026-03-05", dailyGrams: 60, doseSizeGrams: 20)
        #expect(try store.consumptionOverrides(from: "2026-03-02").map(\.startDate) == ["2026-03-05"])
    }

    @Test func coversItsWholeRange() {
        let range = ConsumptionOverride(id: 1, startDate: "2026-03-10", endDate: "2026-03-12", dailyGrams: 60, doseSizeGrams: 20)
        #expect(range.covers("2026-03-10"))
        #expect(range.covers("2026-03-12"))
        #expect(!range.covers("2026-03-13"))
    }

    @Test func scheduleUsesTheOverride() throws {
        try store.db.run(
            "INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived) VALUES ('b1', 'Bean', 'Roaster', '2026-01-01', 250, 0)"
        )
        try store.setConsumptionOverride(date: "2026-02-02", dailyGrams: 60, doseSizeGrams: 20)
        let schedule = try store.schedule(start: "2026-02-01", end: "2026-02-03", today: "2026-01-01")
        func grams(_ date: String) -> Double? {
            schedule.first { $0.date == date }?.consumptions.reduce(0) { $0 + $1.grams }
        }
        #expect(grams("2026-02-01") == 45)
        #expect(grams("2026-02-02") == 60)
        #expect(grams("2026-02-03") == 45)
    }
}
