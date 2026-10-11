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

    @Test func activeFreezeStopsAtTodayWhenNotProjecting() throws {
        try event("b1", "freeze", "2026-01-10")
        try store.db.run("UPDATE beans SET is_frozen = 1, planned_thaw_date = '2026-02-15' WHERE id = 'b1'")
        #expect(try store.frozenDays(today: "2026-02-01", projectToPlannedThaw: false)["b1"] == 22)
    }

    @Test func completedCyclesKeptWhenNotProjecting() throws {
        try event("b1", "freeze", "2026-01-10")
        try event("b1", "thaw", "2026-01-20")
        try event("b1", "freeze", "2026-02-01")
        try store.db.run("UPDATE beans SET is_frozen = 1, planned_thaw_date = '2026-03-01' WHERE id = 'b1'")
        #expect(try store.frozenDays(today: "2026-02-05", projectToPlannedThaw: false)["b1"] == 14)
    }

    @Test func beansCarryBothFrozenCounts() throws {
        try event("b1", "freeze", "2026-01-10")
        try store.db.run("UPDATE beans SET is_frozen = 1, planned_thaw_date = '2026-02-15' WHERE id = 'b1'")
        let bean = try #require(try store.bean(id: "b1", today: "2026-02-01"))
        #expect(bean.frozenDays == 36)
        #expect(bean.frozenDaysToDate == 22)
        #expect(bean.readyDate == "2026-03-08") // Jan 1 + 30 rest + 36 frozen
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

// Ported from the freeze tests in src/__tests__/api/beans.test.ts.
@Suite struct ToggleFreezeTests {
    let store: CoffeeStore

    init() throws {
        store = try CoffeeStore.inMemory()
        for (i, id) in ["b1", "b2", "b3"].enumerated() {
            try store.db.run(
                "INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived, display_order) VALUES (?, 'Bean', 'Roaster', '2026-01-01', 250, 0, ?)",
                [.text(id), .int(Int64(i + 1))]
            )
        }
    }

    func row(_ id: String) throws -> SQLRow {
        try #require(try store.db.query("SELECT * FROM beans WHERE id = ?", [.text(id)]).first)
    }

    func events(_ id: String) throws -> [FreezeEvent] {
        try store.freezeEvents(beanID: id)
    }

    @Test func togglesStateAndLogsEvents() throws {
        #expect(try store.toggleFreeze(id: "b1", today: "2026-02-01") == true)
        #expect(try row("b1").int("is_frozen") == 1)

        #expect(try store.toggleFreeze(id: "b1", today: "2026-02-11") == false)
        #expect(try row("b1").int("is_frozen") == 0)

        let logged = try events("b1")
        #expect(logged.map(\.kind) == [.freeze, .thaw])
        #expect(logged.map(\.date) == ["2026-02-01", "2026-02-11"])
        #expect(try store.frozenDays(today: "2026-03-01")["b1"] == 10)
    }

    @Test func freezingClearsOrderAndResequences() throws {
        try store.toggleFreeze(id: "b1", today: "2026-02-01")
        #expect(try row("b1").int("display_order") == nil)
        #expect(try row("b2").int("display_order") == 1)
        #expect(try row("b3").int("display_order") == 2)
    }

    @Test func thawingLeavesOrderAlone() throws {
        try store.db.run("UPDATE beans SET is_frozen = 1, display_order = NULL WHERE id = 'b1'")
        try store.toggleFreeze(id: "b1", today: "2026-02-01")
        #expect(try row("b1").int("display_order") == nil)
        #expect(try row("b2").int("display_order") == 2)
    }

    @Test func freezingClearsFreezeAfter() throws {
        try store.db.run("UPDATE beans SET freeze_after_grams = 125 WHERE id = 'b1'")
        try store.toggleFreeze(id: "b1", today: "2026-02-01")
        #expect(try row("b1").double("freeze_after_grams") == nil)
    }

    @Test func thawingClearsPlannedThaw() throws {
        try store.db.run("UPDATE beans SET is_frozen = 1, planned_thaw_date = '2026-03-01' WHERE id = 'b1'")
        try store.toggleFreeze(id: "b1", today: "2026-02-01")
        #expect(try row("b1").string("planned_thaw_date") == nil)
    }

    @Test func unknownBagThrows() throws {
        #expect(throws: BeanSettingsError.notFound) {
            try store.toggleFreeze(id: "nope", today: "2026-02-01")
        }
        #expect(try store.db.query("SELECT COUNT(*) AS n FROM freeze_events").first?.int("n") == 0)
    }
}
