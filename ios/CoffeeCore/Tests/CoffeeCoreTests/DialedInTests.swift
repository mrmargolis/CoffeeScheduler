import Foundation
import Testing

@testable import CoffeeCore

private let recipe = CupRecipe(brew: BrewRecipe(grinder: "Femobook A4Z", grindSetting: "1.7", temperatureC: 93, method: "V60"), agitation: .low)

private func cup(_ id: String, at timestamp: Double, verdict: Verdict?, ratings: [SensoryAttribute: Int] = [.finish: -2]) -> CupEvaluation {
    CupEvaluation(
        id: id, beanID: "uuid-1", timestamp: timestamp, date: "2026-10-12", recipe: recipe, ratings: ratings, drawdown: .slow,
        verdict: verdict)
}

private func store() throws -> CoffeeStore {
    let store = try CoffeeStore.inMemory()
    _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()]), timeZone: utc))
    return store
}

private func openExperiment(at time: Double) -> SavedExperiment {
    SavedExperiment(
        id: "x1", beanID: "uuid-1", createdFrom: "e0", createdAt: time, start: recipe,
        experiment: DialInExperiment.custom(DialInMove(.grind, .down), to: "1.8", after: cup("e0", at: time, verdict: nil), grinder: nil))
}

@Suite struct DialedInTests {
    @Test func dialedInGivesNoExperiment() {
        let advice = DialInAdvisor.advise([cup("e1", at: 1, verdict: .dialedIn)], context: DialInContext())
        #expect(advice.next == .dialedIn)
    }

    @Test func aLaterCupWithAnotherVerdictResumesAdvice() {
        let cups = [cup("e1", at: 1, verdict: .dialedIn), cup("e2", at: 2, verdict: .worse)]
        #expect(DialInAdvisor.advise(cups, context: DialInContext()).experiment != nil)
    }

    @Test func dialedInClosesTheOpenExperiment() throws {
        let store = try store()
        try store.saveExperiment(openExperiment(at: 1))
        try store.saveEvaluation(cup("e1", at: 2, verdict: .dialedIn))
        #expect(try store.openExperiment(beanID: "uuid-1") == nil)
        #expect(try store.experiments(beanID: "uuid-1").first?.status == .superseded)
    }

    @Test func anOlderCupMarkedDialedInLeavesTheExperimentOpen() throws {
        let store = try store()
        try store.saveEvaluation(cup("e2", at: 5, verdict: .same))
        try store.saveExperiment(openExperiment(at: 5))
        try store.saveEvaluation(cup("e1", at: 2, verdict: .dialedIn))
        #expect(try store.openExperiment(beanID: "uuid-1") != nil)
    }

    @Test func theDialedInRecipeIsTheNewestCupsWhenItsDialedIn() throws {
        let store = try store()
        try store.saveEvaluation(cup("e1", at: 1, verdict: .better))
        #expect(try store.dialedInCup(beanID: "uuid-1") == nil)

        try store.saveEvaluation(cup("e2", at: 2, verdict: .dialedIn))
        #expect(try store.dialedInCup(beanID: "uuid-1")?.recipe == recipe)

        try store.saveEvaluation(cup("e3", at: 3, verdict: .worse))
        #expect(try store.dialedInCup(beanID: "uuid-1") == nil)
    }

    @Test func theVerdictIsStoredUnderItsOwnName() throws {
        let store = try store()
        try store.saveEvaluation(cup("e1", at: 1, verdict: .dialedIn))
        #expect(try store.db.query("SELECT verdict FROM cup_evaluations").first?.string("verdict") == "dialed_in")
    }
}
