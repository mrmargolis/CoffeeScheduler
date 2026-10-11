import Testing
@testable import CoffeeCore

// Ported from src/__tests__/api/settings.test.ts, plus the store methods the
// Settings screen uses and the rest-day fallback they feed.
@Suite struct RoasterDefaultsTests {
    let store: CoffeeStore

    init() throws {
        store = try CoffeeStore.inMemory()
    }

    func addBean(_ id: String, roaster: String, restDays: Int? = nil) throws {
        try store.db.run(
            "INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived, rest_days) VALUES (?, 'Bean', ?, '2026-01-01', 250, 0, ?)",
            [.text(id), .text(roaster), SQLValue(restDays)]
        )
    }

    @Test func hasDefaultSettings() throws {
        let settings = try store.settings()
        #expect(settings.dailyConsumptionGrams == 45)
        #expect(settings.defaultRestDays == 30)
    }

    @Test func canUpdateSettings() throws {
        try store.updateSettings(ScheduleSettings(dailyConsumptionGrams: 50, defaultRestDays: 30))
        #expect(try store.db.query("SELECT value FROM settings WHERE key = 'daily_consumption_grams'").first?.string("value") == "50")
    }

    @Test func managesRoasterDefaultsInNameOrder() throws {
        try store.setRoasterRestDays("Tim Wendelboe", 21)
        try store.setRoasterRestDays("Square Mile", 28)
        #expect(try store.roasterDefaults() == [
            RoasterDefault(roaster: "Square Mile", restDays: 28),
            RoasterDefault(roaster: "Tim Wendelboe", restDays: 21),
        ])
    }

    @Test func upsertsRoasterDefaults() throws {
        try store.setRoasterRestDays("Square Mile", 28)
        try store.setRoasterRestDays("Square Mile", 35)
        #expect(try store.roasterDefaults() == [RoasterDefault(roaster: "Square Mile", restDays: 35)])
    }

    @Test func nilRemovesARoasterDefault() throws {
        try store.setRoasterRestDays("Square Mile", 28)
        try store.setRoasterRestDays("Square Mile", nil)
        #expect(try store.roasterDefaults().isEmpty)
    }

    @Test func rejectsNegativeRestDays() throws {
        #expect(throws: BeanSettingsError.negativeRestDays) {
            try store.setRoasterRestDays("Square Mile", -1)
        }
    }

    @Test func listsRoastersFromTheBeans() throws {
        try addBean("b1", roaster: "Tim Wendelboe")
        try addBean("b2", roaster: "onyx")
        try addBean("b3", roaster: "Tim Wendelboe")
        try addBean("b4", roaster: "")
        #expect(try store.roasters() == ["onyx", "Tim Wendelboe"])
    }

    @Test func restDaysFallBackFromBagToRoasterToGlobal() throws {
        try addBean("own", roaster: "Square Mile", restDays: 10)
        try addBean("roaster", roaster: "Square Mile")
        try addBean("global", roaster: "Onyx")
        try store.setRoasterRestDays("Square Mile", 21)

        #expect(try store.bean(id: "own")?.effectiveRestDays == 10)
        #expect(try store.bean(id: "roaster")?.effectiveRestDays == 21)
        #expect(try store.bean(id: "global")?.effectiveRestDays == 30)
    }
}
