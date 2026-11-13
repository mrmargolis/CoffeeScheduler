import Testing

@testable import CoffeeCore

/// A bag started before even the shorter of its own and its roaster's rest is over.
@Suite struct EarlyStartTests {
    /// Roasted Jan 1.
    private func bean(own: Int?, roaster: Int, frozenDays: Int = 0, roastDate: String? = "2026-01-01") -> Bean {
        var bean = makeDetailBean(roastDate: roastDate, effectiveRestDays: own ?? roaster, frozenDays: frozenDays)
        bean.restDays = own
        bean.roasterRestDays = roaster
        return bean
    }

    @Test func goesByTheShorterOfTheBagsAndTheRoastersRest() {
        // Its own 30 days, its roaster's 21: early only before day 21
        #expect(bean(own: 30, roaster: 21).daysEarly(startingOn: "2026-01-26") == nil)
        #expect(bean(own: 30, roaster: 21).daysEarly(startingOn: "2026-01-19") == 3)
        // Its own 14 days, shorter than its roaster's
        #expect(bean(own: 14, roaster: 30).daysEarly(startingOn: "2026-01-21") == nil)
        #expect(bean(own: 14, roaster: 30).daysEarly(startingOn: "2026-01-13") == 2)
    }

    @Test func goesByTheRoastersRestForABagWithoutItsOwn() {
        #expect(bean(own: nil, roaster: 30).daysEarly(startingOn: "2026-01-28") == 3)
        #expect(bean(own: nil, roaster: 30).daysEarly(startingOn: "2026-01-31") == nil)
    }

    @Test func leavesOutTimeInTheFreezer() {
        #expect(bean(own: nil, roaster: 30, frozenDays: 7).daysEarly(startingOn: "2026-02-05") == 2)
    }

    @Test func cantTellWithoutARoastDate() {
        #expect(bean(own: nil, roaster: 30, roastDate: nil).daysEarly(startingOn: "2026-01-02") == nil)
    }

    @Test func readsTheRoastersRestOrTheDefault() throws {
        let store = try CoffeeStore.inMemory()
        let beans = [
            bcBean(["roaster": "Onyx", "config": ["uuid": "onyx", "unix_timestamp": 1_700_000_000]]),
            bcBean(["roaster": "Other", "config": ["uuid": "other", "unix_timestamp": 1_700_000_000]]),
        ]
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: beans), timeZone: utc), on: "2026-02-01")
        try store.setRoasterRestDays("onyx ", 21)
        try store.updateBeanSettings(id: "onyx", BeanSettings(restDays: 40))

        let onyx = try #require(try store.bean(id: "onyx"))
        #expect(onyx.roasterRestDays == 21)
        #expect(onyx.minimumRestDays == 21)
        // No roaster default: the global 30 days
        #expect(try store.bean(id: "other")?.roasterRestDays == 30)
    }
}
