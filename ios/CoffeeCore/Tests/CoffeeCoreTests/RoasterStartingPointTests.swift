import Foundation
import Testing

@testable import CoffeeCore

/// Bags from Square Mile (one spelled differently), Onyx, and one with no roaster.
private func store() throws -> CoffeeStore {
    let bean = { (id: String, name: String, roaster: String) in
        bcBean(["name": name, "roaster": roaster, "config": ["uuid": id, "unix_timestamp": 1_700_000_000]])
    }
    let beans = [
        bean("new", "New Guji", "Square Mile"), bean("old", "Old Guji", " square mile "), bean("older", "Kenya", "Square Mile"),
        bean("onyx", "Geometry", "Onyx"), bean("none", "Mystery", ""), bean("none-2", "Mystery 2", ""),
    ]
    let store = try CoffeeStore.inMemory()
    _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: beans), timeZone: utc))
    return store
}

private func cup(_ id: String, bean: String, at timestamp: Double, verdict: Verdict? = .dialedIn, grind: String = "1.6") -> CupEvaluation {
    CupEvaluation(
        id: id, beanID: bean, timestamp: timestamp, date: "2026-10-12",
        recipe: CupRecipe(brew: BrewRecipe(grinder: "Femobook A4Z", grindSetting: grind, temperatureC: 93), agitation: .low),
        verdict: verdict)
}

@Suite struct RoasterStartingPointTests {
    @Test func theNewestDialedInCupFromAnotherBagOfTheRoaster() throws {
        let store = try store()
        try store.saveEvaluation(cup("k", bean: "older", at: 100, grind: "1.5"))
        try store.saveEvaluation(cup("g", bean: "old", at: 200, grind: "1.7"))
        try store.saveEvaluation(cup("g2", bean: "old", at: 300, verdict: .better))

        let start = try #require(try store.roasterStartingPoint(beanID: "new"))
        #expect(start.beanID == "old")
        #expect(start.beanName == "Old Guji")
        #expect(start.cup.recipe.brew.grindSetting == "1.7")
        #expect(start.cup.recipe.agitation == .low)
    }

    @Test func otherRoastersAndTheBagItselfDontCount() throws {
        let store = try store()
        try store.saveEvaluation(cup("o", bean: "onyx", at: 100))
        try store.saveEvaluation(cup("n", bean: "new", at: 200))
        #expect(try store.roasterStartingPoint(beanID: "new") == nil)
    }

    @Test func nothingWithoutADialedInCup() throws {
        let store = try store()
        try store.saveEvaluation(cup("g", bean: "old", at: 100, verdict: .better))
        #expect(try store.roasterStartingPoint(beanID: "new") == nil)
    }

    @Test func bagsWithoutARoasterArentMatchedToEachOther() throws {
        let store = try store()
        try store.saveEvaluation(cup("m", bean: "none-2", at: 100))
        #expect(try store.roasterStartingPoint(beanID: "none") == nil)
    }
}
