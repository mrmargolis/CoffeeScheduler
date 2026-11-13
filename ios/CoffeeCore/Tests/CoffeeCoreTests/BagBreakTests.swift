import Testing

@testable import CoffeeCore

/// Planned rests from a bag without freezing it.
@Suite struct BagBreakTests {
    /// An opened bag, ready, with breaks; and a ready bag to drink meanwhile.
    private func bags(remaining: Double, breaks: [BagBreak]) -> [Scheduler.Bean] {
        var gwo = makeBean(id: "gwo", roastDate: "2025-11-20", remainingGrams: remaining)
        gwo.breaks = breaks
        // Enough to last the break
        let other = makeBean(id: "other", roastDate: "2025-11-25", weightGrams: 1000, remainingGrams: 1000)
        return [gwo, other]
    }

    /// The days, from the first, that `id` is drunk on.
    private func days(of id: String, in days: [ScheduleDay]) -> [Int] {
        days.enumerated().filter { $0.element.consumptions.contains { $0.beanID == id } }.map(\.offset)
    }

    private func grams(of id: String, in days: some Sequence<ScheduleDay>) -> Double {
        days.flatMap(\.consumptions).filter { $0.beanID == id }.reduce(0) { $0 + $1.grams }
    }

    @Test func drinksDownToTheBreakThenOtherBagsUntilItsBack() {
        // 100 g used of 250; a break after 150 g, back on the 11th
        let result = schedule(
            "2026-01-01", "2026-01-14", beans: bags(remaining: 150, breaks: [BagBreak(afterGrams: 150, resumeDate: "2026-01-11")]))
        #expect(days(of: "gwo", in: result).first == 0)
        #expect(!days(of: "gwo", in: result).contains { (1...9).contains($0) })
        #expect(days(of: "other", in: result).starts(with: Array(1...9)))
        // Back on the 11th, ahead of the bag drunk meanwhile
        #expect(result[10].consumptions.first?.beanID == "gwo")
        #expect(result.allSatisfy { !$0.isGap })
    }

    @Test func keepsWhatsLeftAtTheBreakForAfterIt() {
        // 40 g to go before the break: two doses, and the 10 g over stays in the bag
        let result = schedule(
            "2026-01-01", "2026-01-20", beans: bags(remaining: 140, breaks: [BagBreak(afterGrams: 150, resumeDate: "2026-01-11")]))
        #expect(grams(of: "gwo", in: result.prefix(10)) == 30)
        #expect(grams(of: "gwo", in: result.dropFirst(10)) >= 105)
    }

    @Test func startsTheBreakAtOnceWhenItsAlreadyPastTheAmount() {
        // 170 g used: past the 150 g break, so it rests from today
        let result = schedule(
            "2026-01-01", "2026-01-12", beans: bags(remaining: 80, breaks: [BagBreak(afterGrams: 150, resumeDate: "2026-01-08")]))
        #expect(days(of: "gwo", in: result).first == 7)
        #expect(days(of: "other", in: result).first == 0)
    }

    @Test func passesTheBagByWithLessThanADoseBeforeTheBreak() {
        // 13 g above the break: not a whole dose, so the bag rests and isn't counted ready
        let result = schedule(
            "2026-01-01", "2026-01-12", beans: bags(remaining: 113, breaks: [BagBreak(afterGrams: 150, resumeDate: "2026-01-11")]))
        #expect(days(of: "gwo", in: result).first == 10)
        #expect(!result[0].isSurplus)
    }

    @Test func takesNoPartDoseBeforeTheBreakOnASmallDay() {
        // A 13 g day: the 13 g above the break would cover it, but isn't a dose
        let result = schedule(
            "2026-01-01", "2026-01-01", beans: bags(remaining: 113, breaks: [BagBreak(afterGrams: 150, resumeDate: "2026-01-11")]),
            overrides: ["2026-01-01": Scheduler.DayOverride(dailyGrams: 13, doseSize: 15)])
        #expect(result[0].consumptions.map(\.beanID) == ["other"])
    }

    @Test func ignoresABreakThatsOver() {
        let result = schedule(
            "2026-01-01", "2026-01-05", beans: bags(remaining: 150, breaks: [BagBreak(afterGrams: 150, resumeDate: "2026-01-01")]))
        #expect(days(of: "gwo", in: result) == [0, 1, 2, 3])
    }

    @Test func takesSeveralBreaksInTurn() {
        // A full bag: 100 g, rest until the 6th, to 175 g, rest until the 16th, then the rest
        var gwo = makeBean(id: "gwo", roastDate: "2025-11-20", displayOrder: 1)
        gwo.breaks = [
            BagBreak(afterGrams: 175, resumeDate: "2026-01-16"),
            BagBreak(afterGrams: 100, resumeDate: "2026-01-06"),
        ]
        let other = makeBean(id: "other", roastDate: "2025-11-25", weightGrams: 1000, remainingGrams: 1000, displayOrder: 2)
        let result = schedule("2026-01-01", "2026-01-20", beans: [gwo, other])
        let drunk = days(of: "gwo", in: result)
        #expect(drunk.starts(with: [0, 1]))
        #expect(!drunk.contains { (2...4).contains($0) })
        #expect(drunk.contains(5))
        #expect(!drunk.contains { (7...14).contains($0) })
        #expect(drunk.contains(15))
        #expect(grams(of: "gwo", in: result) >= 230)
    }

    @Test func aBreakAndAFreezeTogetherStopAtTheFirstOfThem() {
        var gwo = makeBean(id: "gwo", roastDate: "2025-11-20", freezeAfterGrams: 100)
        gwo.breaks = [BagBreak(afterGrams: 150, resumeDate: "2026-01-05")]
        let result = schedule("2026-01-01", "2026-01-10", beans: [gwo, makeBean(id: "other", roastDate: "2025-11-25")])
        #expect(grams(of: "gwo", in: result) == 90)
    }

    // MARK: - The bag's state

    private func bean(used: Double, breaks: [BagBreak]) -> Bean {
        var bean = makeDetailBean(totalBrewedGrams: used)
        bean.breaks = breaks
        return bean
    }

    @Test func saysWhenTheBagIsOnABreakAndWhichIsNext() {
        let pause = BagBreak(afterGrams: 150, resumeDate: "2026-11-28")
        #expect(bean(used: 100, breaks: [pause]).breakOn("2026-11-13") == nil)
        #expect(bean(used: 100, breaks: [pause]).nextBreak(after: "2026-11-13") == pause)
        // Within a dose of the amount counts as there: the schedule won't take less
        #expect(bean(used: 140, breaks: [pause]).breakOn("2026-11-13") == pause)
        #expect(bean(used: 137, breaks: [pause]).breakOn("2026-11-13") == pause)
        #expect(bean(used: 137, breaks: [pause]).nextBreak(after: "2026-11-13") == nil)
        #expect(bean(used: 135, breaks: [pause]).breakOn("2026-11-13") == nil)
        #expect(bean(used: 160, breaks: [pause]).breakOn("2026-11-13") == pause)
        #expect(bean(used: 160, breaks: [pause]).nextBreak(after: "2026-11-13") == nil)
        // Over on its back-on day
        #expect(bean(used: 160, breaks: [pause]).breakOn("2026-11-28") == nil)
    }

    // MARK: - Saving

    private func storeWithABag() throws -> CoffeeStore {
        let store = try CoffeeStore.inMemory()
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()]), timeZone: utc), on: "2026-02-01")
        return store
    }

    @Test func savesTheBreaksWithTheBagsSettingsInTheirOrder() throws {
        let store = try storeWithABag()
        let later = BagBreak(afterGrams: 200, resumeDate: "2026-04-01")
        let sooner = BagBreak(afterGrams: 100, resumeDate: "2026-03-01")
        try store.updateBeanSettings(id: "uuid-1", BeanSettings(breaks: [later, sooner]))
        #expect(try store.bean(id: "uuid-1")?.breaks == [sooner, later])

        // Saving again replaces them
        try store.updateBeanSettings(id: "uuid-1", BeanSettings(breaks: [later]))
        #expect(try store.bean(id: "uuid-1")?.breaks == [later])
        try store.updateBeanSettings(id: "uuid-1", BeanSettings())
        #expect(try store.bean(id: "uuid-1")?.breaks == [])
    }

    @Test func schedulesTheSavedBreaks() throws {
        let store = try storeWithABag()
        // As the Edit screen saves it: the bag's settings, with a break added
        var settings = BeanSettings(try #require(try store.bean(id: "uuid-1")))
        settings.breaks = [BagBreak(afterGrams: 90, resumeDate: "2026-02-10")]
        try store.updateBeanSettings(id: "uuid-1", settings)
        let days = try store.schedule(start: "2026-02-01", end: "2026-02-12", today: "2026-02-01")
        #expect(self.days(of: "uuid-1", in: days) == [0, 1, 9, 10, 11])
    }

    @Test func refusesABreakThatLeavesNothingOnOneSide() throws {
        let store = try storeWithABag()
        for grams in [0.0, 250, 300] {
            #expect(throws: BeanSettingsError.breakOutOfRange(weightGrams: 250)) {
                try store.updateBeanSettings(id: "uuid-1", BeanSettings(breaks: [BagBreak(afterGrams: grams, resumeDate: "2026-03-01")]))
            }
        }
        #expect(throws: BeanSettingsError.invalidDate("soon")) {
            try store.updateBeanSettings(id: "uuid-1", BeanSettings(breaks: [BagBreak(afterGrams: 100, resumeDate: "soon")]))
        }
    }
}
