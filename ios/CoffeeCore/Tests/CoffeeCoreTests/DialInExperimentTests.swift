import Foundation
import Testing

@testable import CoffeeCore

private let startRecipe = CupRecipe(
    brew: BrewRecipe(
        grinder: "Femobook A4Z", grindSetting: "1.6", temperatureC: 93, doseGrams: 15, waterGrams: 240, method: "V60",
        water: "Barista Tears"),
    agitation: .medium)

/// "Grind coarser 1.6 → 1.7", aimed at finish (−2) and sweetness (−1).
private let finishAndSweetness: [SensoryAttribute: Int] = [.finish: -2, .sweetness: -1]

private func grindExperiment(targets: [SensoryAttribute: Int] = finishAndSweetness, tags: [CharacterTag] = []) -> DialInExperiment {
    DialInExperiment(
        move: DialInMove(.grind, .down), from: "Femobook A4Z 1.6", to: "1.7", toValue: 1.7, targets: targets, targetTags: tags,
        numberDirection: 1, expectedEffect: "Longer finish", criteria: [])
}

private func saved(
    _ experiment: DialInExperiment = grindExperiment(), id: String = "x1", at createdAt: Double = 100,
    status: ExperimentStatus = .open, outcome: ExperimentOutcome? = nil, start: CupRecipe = startRecipe
) -> SavedExperiment {
    SavedExperiment(
        id: id, beanID: "uuid-1", createdFrom: "e0", createdAt: createdAt, start: start, experiment: experiment, status: status,
        outcome: outcome)
}

/// The next cup: the start recipe with `change` applied, rated as given.
private func nextCup(
    _ ratings: [SensoryAttribute: Int], character: [CharacterTag] = [], id: String = "e1", at timestamp: Double = 200,
    _ change: (inout CupRecipe) -> Void = { $0.brew.grindSetting = "1.7" }
) -> CupEvaluation {
    var recipe = startRecipe
    change(&recipe)
    return CupEvaluation(
        id: id, beanID: "uuid-1", timestamp: timestamp, date: "2026-10-12", recipe: recipe, ratings: ratings,
        character: Dictionary(uniqueKeysWithValues: character.map { ($0, TagSource.user) }))
}

@Suite struct ExperimentOutcomeTests {
    @Test func improvedWhenEveryTargetIsCloser() {
        #expect(saved().outcome(of: nextCup([.finish: -1, .sweetness: 0])) == .improved)
    }

    @Test func unchangedWhenNoneIsFurtherButNotAllCloser() {
        #expect(saved().outcome(of: nextCup([.finish: -1, .sweetness: -1])) == .unchanged)
        // An unrated target counts as no change
        #expect(saved().outcome(of: nextCup([.finish: -1])) == .unchanged)
    }

    @Test func worseWhenAnyTargetIsFurther() {
        #expect(saved().outcome(of: nextCup([.finish: 0, .sweetness: -2])) == .worse)
    }

    @Test func overshootingStillCountsAsCloser() {
        #expect(saved().outcome(of: nextCup([.finish: 1, .sweetness: 0])) == .improved)
    }

    @Test func aTargetTagGoneCountsAsBetter() {
        let bitter = grindExperiment(targets: [:], tags: [.bitter])
        #expect(saved(bitter).outcome(of: nextCup([:])) == .improved)
        #expect(saved(bitter).outcome(of: nextCup([:], character: [.bitter])) == .unchanged)
    }

    @Test func notTestedWhenNothingChangedSoItStaysOpen() {
        #expect(saved().outcome(of: nextCup([.finish: 0]) { _ in }) == nil)
    }

    @Test func confoundedWhenSomethingElseChangedToo() {
        #expect(
            saved().outcome(
                of: nextCup([.finish: 0]) {
                    $0.brew.grindSetting = "1.7"
                    $0.brew.temperatureC = 95
                }) == .confounded)
        #expect(
            saved().outcome(
                of: nextCup([.finish: 0]) {
                    $0.brew.grindSetting = "1.7"
                    $0.agitation = .low
                }) == .confounded)
        #expect(
            saved().outcome(
                of: nextCup([.finish: 0]) {
                    $0.brew.grindSetting = "1.7"
                    $0.brew.water = "Lotus"
                }) == .confounded)
        #expect(
            saved().outcome(
                of: nextCup([.finish: 0]) {
                    $0.brew.grindSetting = "1.7"
                    $0.brew.waterGrams = 255
                }) == .confounded)
    }

    @Test func confoundedWhenOnlySomethingElseChanged() {
        #expect(saved().outcome(of: nextCup([.finish: 0]) { $0.brew.temperatureC = 95 }) == .confounded)
    }

    @Test func aMoveTheWrongWayIsADifferentChange() {
        #expect(saved().outcome(of: nextCup([.finish: 0]) { $0.brew.grindSetting = "1.5" }) == .confounded)
    }

    @Test func anotherGrinderOrMethodIsNotComparable() {
        #expect(saved().outcome(of: nextCup([.finish: 0]) { $0.brew.grinder = "Fellow Ode 2" }) == .notComparable)
        #expect(saved().outcome(of: nextCup([.finish: 0]) { $0.brew.method = "Hario Switch" }) == .notComparable)
    }

    @Test func movingFurtherThanSuggestedStillTestsIt() {
        #expect(saved().outcome(of: nextCup([.finish: -1, .sweetness: 0]) { $0.brew.grindSetting = "1.8" }) == .improved)
    }
}

@Suite struct GrindLimitTests {
    private func decided(_ id: String, at time: Double, _ variable: DialInVariable, _ outcome: ExperimentOutcome) -> SavedExperiment {
        let move = DialInExperiment(
            move: DialInMove(variable, .down), from: nil, to: nil, toValue: nil, targets: [:], targetTags: [], numberDirection: 1,
            expectedEffect: "", criteria: [])
        return saved(move, id: id, at: time, status: .decided, outcome: outcome)
    }

    @Test func twoGrindExperimentsThatDidntHelpBlockGrind() {
        let experiments = [decided("a", at: 1, .grind, .unchanged), decided("b", at: 2, .grind, .worse)]
        #expect(DialInLimits.blocked(experiments, grinder: "Femobook A4Z", method: "V60") == [.grind])
    }

    @Test func anImprovementKeepsGrindOpen() {
        let experiments = [decided("a", at: 1, .grind, .unchanged), decided("b", at: 2, .grind, .improved)]
        #expect(DialInLimits.blocked(experiments, grinder: "Femobook A4Z", method: "V60").isEmpty)
    }

    @Test func confoundedAndNotComparableDontCount() {
        let experiments = [
            decided("a", at: 1, .grind, .unchanged), decided("b", at: 2, .grind, .confounded),
            decided("c", at: 3, .grind, .notComparable), decided("d", at: 4, .grind, .worse),
        ]
        #expect(DialInLimits.blocked(experiments, grinder: "Femobook A4Z", method: "V60") == [.grind])
    }

    @Test func aCleanNonGrindExperimentInBetweenResetsIt() {
        let experiments = [decided("a", at: 1, .grind, .unchanged), decided("b", at: 2, .temperature, .unchanged)]
        #expect(DialInLimits.blocked(experiments, grinder: "Femobook A4Z", method: "V60").isEmpty)
    }

    @Test func itsPerGrinderAndMethod() {
        let experiments = [decided("a", at: 1, .grind, .unchanged), decided("b", at: 2, .grind, .worse)]
        #expect(DialInLimits.blocked(experiments, grinder: "Fellow Ode 2", method: "V60").isEmpty)
        #expect(DialInLimits.blocked(experiments, grinder: "Femobook A4Z", method: "Hario Switch").isEmpty)
    }

    @Test func theAdvisorMovesOffGrind() {
        let cup = CupEvaluation(
            beanID: "b", timestamp: 1, date: "2026-10-12", recipe: startRecipe, ratings: [.finish: -2], drawdown: .slow)
        let advice = DialInAdvisor.advise([cup], context: DialInContext(blocked: [.grind]))
        #expect(advice.experiment?.move == DialInMove(.agitation, .down))
    }
}

@Suite struct ExperimentStoreTests {
    private func store() throws -> CoffeeStore {
        let store = try CoffeeStore.inMemory()
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()]), timeZone: utc))
        return store
    }

    @Test func savesAndReadsBackAnExperiment() throws {
        let store = try store()
        let experiment = saved(grindExperiment(tags: [.muddy]))
        try store.saveExperiment(experiment)
        #expect(try store.experiments(beanID: "uuid-1") == [experiment])
        #expect(try store.openExperiment(beanID: "uuid-1") == experiment)
    }

    @Test func onlyOneIsOpenAtATime() throws {
        let store = try store()
        try store.saveExperiment(saved(id: "first", at: 100))
        try store.saveExperiment(saved(id: "second", at: 150))
        #expect(try store.openExperiment(beanID: "uuid-1")?.id == "second")
        #expect(try store.experiments(beanID: "uuid-1").map(\.status) == [.open, .superseded])
    }

    @Test func dismissing() throws {
        let store = try store()
        try store.saveExperiment(saved())
        try store.dismissExperiment(id: "x1")
        #expect(try store.openExperiment(beanID: "uuid-1") == nil)
        #expect(try store.experiments(beanID: "uuid-1").first?.status == .dismissed)
    }

    @Test func theNextCupDecidesIt() throws {
        let store = try store()
        try store.saveExperiment(saved())
        let decided = try #require(try store.decideOpenExperiment(with: nextCup([.finish: -1, .sweetness: 0])))
        #expect(decided.outcome == .improved)
        #expect(decided.decidedBy == "e1")
        #expect(try store.openExperiment(beanID: "uuid-1") == nil)
    }

    @Test func aCupThatDidntTestItLeavesItOpen() throws {
        let store = try store()
        try store.saveExperiment(saved())
        #expect(try store.decideOpenExperiment(with: nextCup([.finish: 0]) { _ in }) == nil)
        #expect(try store.openExperiment(beanID: "uuid-1")?.id == "x1")
    }

    @Test func anEarlierCupDoesntDecideIt() throws {
        let store = try store()
        try store.saveExperiment(saved(at: 300))
        #expect(try store.decideOpenExperiment(with: nextCup([.finish: 0], at: 200)) == nil)
    }

    @Test func aDecisionStaysWhenTheCupIsEditedLater() throws {
        let store = try store()
        try store.saveExperiment(saved())
        var cup = nextCup([.finish: -1, .sweetness: 0])
        try store.saveEvaluation(cup)
        try store.decideOpenExperiment(with: cup)

        cup.recipe.brew.temperatureC = 99
        cup.ratings = [.finish: -2]
        try store.saveEvaluation(cup)
        #expect(try store.decideOpenExperiment(with: cup) == nil)
        #expect(try store.experiments(beanID: "uuid-1").first?.outcome == .improved)
    }

    @Test func blockedVariablesComeFromTheBagsExperiments() throws {
        let store = try store()
        for (i, outcome) in [ExperimentOutcome.unchanged, .worse].enumerated() {
            try store.saveExperiment(saved(id: "x\(i)", at: Double(i), status: .decided, outcome: outcome))
        }
        #expect(try store.blockedVariables(beanID: "uuid-1", grinder: "Femobook A4Z", method: "V60") == [.grind])
    }
}

@Suite struct CustomExperimentTests {
    @Test func aimsAtWhatsOffAndTakesTheTypedValue() {
        let cup = nextCup([.finish: -2, .body: 0, .acidity: 1], character: [.muddy]) { _ in }
        let experiment = DialInExperiment.custom(DialInMove(.temperature, .down), to: " 91 ", after: cup, grinder: nil)
        #expect(experiment.instruction == "Cooler water: 93 °C → 91")
        #expect(experiment.toValue == 91)
        #expect(experiment.targets == [.finish: -2, .acidity: 1])
        #expect(experiment.targetTags == [.muddy])
        #expect(experiment.numberDirection == -1)
    }

    @Test func withoutAValueItsADirection() {
        let cup = nextCup([.finish: -2]) { _ in }
        let experiment = DialInExperiment.custom(DialInMove(.agitation, .down), to: "", after: cup, grinder: nil)
        #expect(experiment.instruction == "Less agitation by one step")
    }

    @Test func itsDecidedLikeAnyOther() {
        let cup = nextCup([.finish: -2]) { _ in }
        let experiment = DialInExperiment.custom(DialInMove(.grind, .down), to: "1.7", after: cup, grinder: nil)
        #expect(saved(experiment).outcome(of: nextCup([.finish: -1])) == .improved)
    }
}
