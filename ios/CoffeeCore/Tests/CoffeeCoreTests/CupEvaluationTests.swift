import Foundation
import Testing

@testable import CoffeeCore

/// A brew of uuid-1 logged at `timestamp`, with a recipe.
private func recipeBrew(_ id: String, at timestamp: Int, grind: Double = 1.6) -> [String: Any] {
    bcBrew([
        "config": ["uuid": id, "unix_timestamp": timestamp], "grind_size": grind, "brew_temperature": 93,
        "brew_quantity": 240, "brew_time": 208, "pressure_profile": "Four Pour",
    ])
}

/// A store holding bean uuid-1 and the given brews.
private func store(brews: [[String: Any]] = []) throws -> CoffeeStore {
    let store = try CoffeeStore.inMemory()
    _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()], brews: brews), timeZone: utc))
    return store
}

/// An evaluation of uuid-1 with sensible defaults.
private func makeEvaluation(
    _ id: String = "e1", at timestamp: Double = 1_706_790_000, recipe: CupRecipe = CupRecipe(),
    ratings: [SensoryAttribute: Int] = [:]
) -> CupEvaluation {
    CupEvaluation(id: id, beanID: "uuid-1", timestamp: timestamp, date: "2024-02-01", recipe: recipe, ratings: ratings)
}

@Suite struct CupEvaluationStoreTests {
    @Test func savesAndReadsBackEveryField() throws {
        let store = try store()
        let evaluation = CupEvaluation(
            id: "e1", beanID: "uuid-1", timestamp: 1_706_790_000, date: "2024-02-01",
            recipe: CupRecipe(
                brew: BrewRecipe(
                    grinder: "A4Z", grindSetting: "1.6", temperatureC: 93, doseGrams: 15, waterGrams: 240, method: "V60",
                    water: "Lotus", profile: "Four Pour"),
                agitation: .medium),
            ratings: [.sweetness: -1, .finish: -2, .clarity: 0],
            drawdown: .slow, flowProblem: true, verdict: .better)
        try store.saveEvaluation(evaluation)

        #expect(try store.evaluations(beanID: "uuid-1") == [evaluation])
    }

    @Test func unratedAttributesStayUnrated() throws {
        let store = try store()
        try store.saveEvaluation(makeEvaluation(ratings: [.body: 1]))

        let saved = try #require(try store.evaluations(beanID: "uuid-1").first)
        #expect(saved.ratings == [.body: 1])
        #expect(saved.drawdown == nil)
        #expect(saved.verdict == nil)
        #expect(saved.flowProblem == false)
    }

    @Test func recipeTextIsTrimmedAndBlankIsUnknown() throws {
        let store = try store()
        let typed = CupRecipe(brew: BrewRecipe(grinder: " Femobook A4Z ", grindSetting: "1.7 ", method: "   "))
        try store.saveEvaluation(makeEvaluation(recipe: typed))
        #expect(try store.evaluations(beanID: "uuid-1").first?.recipe.brew == BrewRecipe(grinder: "Femobook A4Z", grindSetting: "1.7"))
    }

    @Test func ratingsOutsideTheScaleAreClamped() throws {
        let store = try store()
        try store.saveEvaluation(makeEvaluation(ratings: [.acidity: 5, .body: -9]))
        #expect(try store.evaluations(beanID: "uuid-1").first?.ratings == [.acidity: 2, .body: -2])
    }

    @Test func editsReplaceAndDeletesRemove() throws {
        let store = try store()
        try store.saveEvaluation(makeEvaluation(ratings: [.body: 1]))
        try store.saveEvaluation(makeEvaluation(ratings: [.body: 0]))
        #expect(try store.evaluations(beanID: "uuid-1").map(\.ratings) == [[.body: 0]])

        try store.deleteEvaluation(id: "e1")
        #expect(try store.evaluations(beanID: "uuid-1").isEmpty)
    }

    @Test func listsTheBagsEvaluationsNewestFirst() throws {
        let store = try CoffeeStore.inMemory()
        let beans = [bcBean(), bcBean(["config": ["uuid": "uuid-2", "unix_timestamp": 1_700_000_000]])]
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: beans), timeZone: utc))
        try store.saveEvaluation(makeEvaluation("early", at: 100))
        try store.saveEvaluation(makeEvaluation("late", at: 300))
        try store.saveEvaluation(makeEvaluation("middle", at: 200))
        var other = makeEvaluation("other", at: 400)
        other.beanID = "uuid-2"
        try store.saveEvaluation(other)

        #expect(try store.evaluations(beanID: "uuid-1").map(\.id) == ["late", "middle", "early"])
    }

    @Test func evaluationsSurviveAReimport() throws {
        let store = try store(brews: [recipeBrew("brew-1", at: 1_706_788_800)])
        try store.saveEvaluation(makeEvaluation())
        _ = try store.importExport(
            BeanConquerorParser.parse(
                zipData: try makeExport(beans: [bcBean()], brews: [recipeBrew("brew-1", at: 1_706_788_800)]), timeZone: utc))

        #expect(try store.evaluations(beanID: "uuid-1").map(\.id) == ["e1"])
    }
}

@Suite struct CurrentRecipeTests {
    @Test func startsFromTheLatestBrewWithoutItsBrewTime() throws {
        let store = try store(brews: [recipeBrew("brew-1", at: 1_706_788_800)])

        let recipe = try store.currentRecipe(beanID: "uuid-1")
        #expect(recipe.brew == BrewRecipe(grindSetting: "1.6", temperatureC: 93, doseGrams: 15, waterGrams: 240, profile: "Four Pour"))
        #expect(recipe.agitation == nil)
    }

    @Test func aNewerEvaluationWinsOverAnOlderBrew() throws {
        let store = try store(brews: [recipeBrew("brew-1", at: 1_706_788_800)])
        let typed = CupRecipe(brew: BrewRecipe(grindSetting: "1.7", temperatureC: 91), agitation: .low)
        try store.saveEvaluation(makeEvaluation(at: 1_706_790_000, recipe: typed))

        #expect(try store.currentRecipe(beanID: "uuid-1") == typed)
    }

    @Test func aNewerBrewWinsButKeepsTheEvaluationsAgitation() throws {
        let store = try store(brews: [recipeBrew("brew-2", at: 1_706_800_000, grind: 1.8)])
        let typed = CupRecipe(brew: BrewRecipe(grindSetting: "1.7"), agitation: .high)
        try store.saveEvaluation(makeEvaluation(at: 1_706_790_000, recipe: typed))

        let recipe = try store.currentRecipe(beanID: "uuid-1")
        #expect(recipe.brew.grindSetting == "1.8")
        #expect(recipe.agitation == .high)
    }

    @Test func emptyWithNoBrewsOrEvaluations() throws {
        #expect(try store().currentRecipe(beanID: "uuid-1") == CupRecipe())
    }
}

@Suite struct CupRecipeChangeTests {
    @Test func namesEachChangedField() {
        let before = CupRecipe(brew: BrewRecipe(grinder: "A4Z", grindSetting: "1.6", temperatureC: 93, waterGrams: 240), agitation: .medium)
        let after = CupRecipe(brew: BrewRecipe(grinder: "A4Z", grindSetting: "1.7", temperatureC: 91, waterGrams: 240), agitation: .low)
        #expect(after.changes(from: before) == ["Grind 1.6 → 1.7", "Temperature 93 → 91 °C", "Agitation medium → low"])
    }

    @Test func unknownSidesShowAsAQuestionMark() {
        let before = CupRecipe(brew: BrewRecipe(doseGrams: 15))
        let after = CupRecipe(brew: BrewRecipe(method: "V60"))
        #expect(after.changes(from: before) == ["Dose 15 → ?", "Method ? → V60"])
    }

    @Test func nothingForTheSameRecipe() {
        let recipe = CupRecipe(brew: BrewRecipe(grindSetting: "1.6"), agitation: .low)
        #expect(recipe.changes(from: recipe).isEmpty)
    }
}

@Suite struct CupRatingTests {
    @Test func labels() {
        #expect(
            [-2, -1, 0, 1, 2, nil].map(CupRating.label) == [
                "Much too low", "Slightly low", "On target", "Slightly high", "Much too high", "Not evaluated",
            ])
    }

    @Test func aNewEvaluationIsOnTheLocalDay() {
        // 2024-02-01 23:30 UTC is already 2 February in Tokyo
        let time = Date(timeIntervalSince1970: 1_706_830_200)
        let tokyo = CupEvaluation.new(beanID: "b", at: time, timeZone: TimeZone(identifier: "Asia/Tokyo")!, recipe: CupRecipe())
        #expect(tokyo.date == "2024-02-02")
        #expect(tokyo.ratings.isEmpty)
        #expect(CupEvaluation.new(beanID: "b", at: time, timeZone: utc, recipe: CupRecipe()).date == "2024-02-01")
    }
}
