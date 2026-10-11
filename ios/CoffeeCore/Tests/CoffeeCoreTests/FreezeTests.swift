import Testing
@testable import CoffeeCore

// Ported from src/__tests__/lib/freeze-utils.test.ts.

@Suite struct EffectiveAgeTests {
    @Test func calendarAgeMinusFrozenDays() {
        #expect(effectiveAge(roastDate: "2026-01-01", asOf: "2026-04-01", frozenDays: 30) == 60)
    }

    @Test func calendarAgeWhenNeverFrozen() {
        #expect(effectiveAge(roastDate: "2026-01-01", asOf: "2026-04-01", frozenDays: 0) == 90)
    }

    @Test func nilWithoutRoastDate() {
        #expect(effectiveAge(roastDate: nil, asOf: "2026-04-01", frozenDays: 0) == nil)
    }

    @Test func flooredAtZero() {
        #expect(effectiveAge(roastDate: "2026-01-01", asOf: "2026-01-10", frozenDays: 30) == 0)
    }
}

@Suite struct FrozenDaysTests {
    let store: CoffeeStore

    init() throws {
        store = try CoffeeStore.inMemory()
        try addBean("b1", roastDate: "2026-01-01")
    }

    func addBean(_ id: String, roastDate: String) throws {
        try store.db.run(
            "INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived) VALUES (?, 'Bean', 'Roaster', ?, 250, 0)",
            [.text(id), .text(roastDate)]
        )
    }

    func event(_ beanID: String, _ kind: String, _ date: String) throws {
        try store.db.run(
            "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, ?, ?)",
            [.text(beanID), .text(kind), .text(date)]
        )
    }

    @Test func noEventsMeansNoEntry() throws {
        #expect(try store.frozenDays(today: "2026-03-01")["b1"] == nil)
    }

    @Test func oneBalancedPair() throws {
        try event("b1", "freeze", "2026-01-10")
        try event("b1", "thaw", "2026-02-09")
        #expect(try store.frozenDays(today: "2026-03-01")["b1"] == 30)
    }

    @Test func multipleCycles() throws {
        try event("b1", "freeze", "2026-01-10")
        try event("b1", "thaw", "2026-01-20")
        try event("b1", "freeze", "2026-02-01")
        try event("b1", "thaw", "2026-02-15")
        #expect(try store.frozenDays(today: "2026-03-01")["b1"] == 24)
    }

    @Test func activeFreezeCountsToToday() throws {
        try event("b1", "freeze", "2026-01-10")
        try store.db.run("UPDATE beans SET is_frozen = 1 WHERE id = 'b1'")
        #expect(try store.frozenDays(today: "2026-02-09")["b1"] == 30)
    }

    @Test func activeFreezeCountsToPlannedThaw() throws {
        try event("b1", "freeze", "2026-01-10")
        try store.db.run("UPDATE beans SET is_frozen = 1, planned_thaw_date = '2026-02-15' WHERE id = 'b1'")
        #expect(try store.frozenDays(today: "2026-02-01")["b1"] == 36)
    }

    @Test func completedCyclePlusActiveFreeze() throws {
        try event("b1", "freeze", "2026-01-10")
        try event("b1", "thaw", "2026-01-20")
        try event("b1", "freeze", "2026-02-01")
        try store.db.run("UPDATE beans SET is_frozen = 1 WHERE id = 'b1'")
        #expect(try store.frozenDays(today: "2026-02-15")["b1"] == 24)
    }

    @Test func strayThawIsIgnored() throws {
        try event("b1", "thaw", "2026-01-20")
        #expect(try store.frozenDays(today: "2026-03-01")["b1"] == nil)
    }

    @Test func perBeanIndependently() throws {
        try addBean("b2", roastDate: "2026-01-15")
        try event("b1", "freeze", "2026-01-10")
        try event("b1", "thaw", "2026-01-25")
        try event("b2", "freeze", "2026-02-01")
        try event("b2", "thaw", "2026-02-08")
        let frozen = try store.frozenDays(today: "2026-03-01")
        #expect(frozen["b1"] == 15)
        #expect(frozen["b2"] == 7)
    }
}
