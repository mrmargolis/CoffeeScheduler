import Testing

@testable import CoffeeCore

@Suite struct BeanSettingsTests {
    let store: CoffeeStore

    init() throws {
        store = try CoffeeStore.inMemory()
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()]), timeZone: utc))
    }

    func bean() throws -> Bean {
        try #require(try store.bean(id: "uuid-1", today: "2026-02-01"))
    }

    @Test func startsFromTheBagsCurrentSettings() throws {
        #expect(BeanSettings(try bean()) == BeanSettings(roastDate: "2026-01-15"))
    }

    @Test func savesEveryField() throws {
        let settings = BeanSettings(restDays: 14, roastDate: "2026-01-10", plannedThawDate: "2026-03-01", freezeAfterGrams: 125)
        try store.updateBeanSettings(id: "uuid-1", settings)
        let saved = try bean()
        #expect(BeanSettings(saved) == settings)
        #expect(saved.effectiveRestDays == 14)
        #expect(saved.readyDate == "2026-01-24")
    }

    @Test func nilClearsAndRestFallsBackToDefaults() throws {
        try store.updateBeanSettings(id: "uuid-1", BeanSettings(restDays: 14, freezeAfterGrams: 125))
        try store.db.run("INSERT INTO roaster_defaults (roaster, rest_days) VALUES ('Test Roaster', 21)")
        try store.updateBeanSettings(id: "uuid-1", BeanSettings())
        let saved = try bean()
        #expect(saved.restDays == nil)
        #expect(saved.roastDate == nil)
        #expect(saved.freezeAfterGrams == nil)
        #expect(saved.effectiveRestDays == 21)  // roaster default
        #expect(saved.readyDate == nil)
    }

    @Test func zeroRestDaysIsAllowed() throws {
        try store.updateBeanSettings(id: "uuid-1", BeanSettings(restDays: 0, roastDate: "2026-01-15"))
        #expect(try bean().readyDate == "2026-01-15")
    }

    @Test func rejectsInvalidValues() throws {
        #expect(throws: BeanSettingsError.negativeRestDays) {
            try store.updateBeanSettings(id: "uuid-1", BeanSettings(restDays: -1))
        }
        #expect(throws: BeanSettingsError.invalidDate("2026-02-30x")) {
            try store.updateBeanSettings(id: "uuid-1", BeanSettings(roastDate: "2026-02-30x"))
        }
        #expect(throws: BeanSettingsError.freezeAfterOutOfRange(weightGrams: 250)) {
            try store.updateBeanSettings(id: "uuid-1", BeanSettings(freezeAfterGrams: 300))
        }
        #expect(throws: BeanSettingsError.notFound) {
            try store.updateBeanSettings(id: "missing", BeanSettings())
        }
        // Nothing was written by the rejected saves
        #expect(BeanSettings(try bean()) == BeanSettings(roastDate: "2026-01-15"))
    }

    @Test func plannedThawInThePastThawsOnNextAutoThaw() throws {
        try store.db.run("UPDATE beans SET is_frozen = 1 WHERE id = 'uuid-1'")
        try store.updateBeanSettings(id: "uuid-1", BeanSettings(roastDate: "2026-01-15", plannedThawDate: "2026-02-01"))
        try store.autoThaw(today: "2026-02-01")
        #expect(try bean().isFrozen == false)
    }

    @Test func freezeAfterReachedFreezesOnNextAutoFreeze() throws {
        try store.db.run("INSERT INTO brews (bean_id, ground_coffee_grams, creation_date) VALUES ('uuid-1', 100, '2026-01-30')")
        try store.updateBeanSettings(id: "uuid-1", BeanSettings(roastDate: "2026-01-15", freezeAfterGrams: 110))
        try store.autoFreeze(today: "2026-02-01")
        #expect(try bean().isFrozen)
    }
}
