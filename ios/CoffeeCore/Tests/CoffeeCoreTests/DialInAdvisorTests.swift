import Foundation
import Testing

@testable import CoffeeCore

/// An A4Z history that makes 0.1 its step and 1.3–1.9 its usual range.
private let a4zHistory = GrinderHistory(runs: [[1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.8, 1.7, 1.6, 1.5, 1.4]])

private func a4z(step: Double? = nil, higherIsCoarser: Bool = true) -> GrinderSetting {
    GrinderSetting(name: "Femobook A4Z", step: step, higherIsCoarser: higherIsCoarser, history: a4zHistory)
}

private let usualRecipe = CupRecipe(
    brew: BrewRecipe(grinder: "Femobook A4Z", grindSetting: "1.6", temperatureC: 93, doseGrams: 15, waterGrams: 240, method: "V60"),
    agitation: .medium)

/// A cup with the usual recipe and only what's given rated.
private func makeCup(
    _ ratings: [SensoryAttribute: Int] = [:], drawdown: Drawdown? = nil, flowProblem: Bool = false,
    character: [CharacterTag] = [], recipe: CupRecipe = usualRecipe
) -> CupEvaluation {
    CupEvaluation(
        beanID: "b", timestamp: 1, date: "2026-10-11", recipe: recipe, ratings: ratings, drawdown: drawdown, flowProblem: flowProblem,
        character: Dictionary(uniqueKeysWithValues: character.map { ($0, TagSource.user) }))
}

private func advise(_ cup: CupEvaluation, _ context: DialInContext = DialInContext(grinder: a4z())) -> DialInAdvice {
    DialInAdvisor.advise([cup], context: context)
}

private func instruction(_ cup: CupEvaluation, _ context: DialInContext = DialInContext(grinder: a4z())) -> String? {
    advise(cup, context).experiment?.instruction
}

@Suite struct DialInRuleTests {
    @Test(arguments: [
        (makeCup([.clarity: -1], flowProblem: true), "The bed stalled or channelled.", "Less agitation: medium → low"),
        (makeCup([.finish: -2], drawdown: .slow), "A slow drawdown with low clarity, finish or sweetness.", "Grind coarser: Femobook A4Z 1.6 → 1.7"),
        (makeCup([.intensity: -1], drawdown: .fast), "A fast drawdown with low intensity.", "Grind finer: Femobook A4Z 1.6 → 1.5"),
        (
            makeCup([.intensity: -1, .sweetness: -1, .acidity: -1]), "Intensity, sweetness and acidity all low.",
            "Grind finer: Femobook A4Z 1.6 → 1.5"
        ),
        (makeCup([.sweetness: -1], character: [.sharp]), "Low sweetness with sharp acidity.", "Grind finer: Femobook A4Z 1.6 → 1.5"),
        (makeCup([.acidity: 0], character: [.bitter]), "Bitterness.", "Cooler water: 93 °C → 91 °C"),
        (makeCup([.clarity: -1, .intensity: 0]), "Muddy, or low clarity with enough intensity.", "Less agitation: medium → low"),
        (makeCup([.body: 1]), "Too much body.", "Less agitation: medium → low"),
        (makeCup([.acidity: -1, .sweetness: 0]), "Low acidity with enough sweetness.", "Grind coarser: Femobook A4Z 1.6 → 1.7"),
        (
            makeCup([.intensity: -1, .sweetness: 0, .body: 0]), "Low intensity in an otherwise good cup.",
            "Shorter ratio: 1:16 (240 g) → 1:15 (225 g)"
        ),
        (makeCup([.intensity: 2]), "Too intense.", "Longer ratio: 1:16 (240 g) → 1:17 (255 g)"),
        (makeCup([.sweetness: -1, .finish: -1]), "Low sweetness.", "Hotter water: 93 °C → 95 °C"),
    ])
    func eachRuleFiresOnItsPattern(cup: CupEvaluation, pattern: String, expected: String) {
        let advice = advise(cup)
        #expect(advice.diagnosis.first == pattern)
        #expect(advice.experiment?.instruction == expected)
    }

    @Test func anEarlierRuleWinsWhenSeveralMatch() {
        // Slow drawdown (rule 2) and all three low (rule 4)
        let cup = makeCup([.intensity: -1, .sweetness: -1, .acidity: -1], drawdown: .slow)
        #expect(advise(cup).diagnosis.first == "A slow drawdown with low clarity, finish or sweetness.")
    }

    @Test func unratedAttributesDontCountAsNotLow() {
        // Low clarity, but intensity unrated: not rule 7, and nothing else matches
        #expect(advise(makeCup([.clarity: -1])).next == .noSuggestion)
    }

    @Test func characterRulesNeedTheirTags() {
        // Low sweetness alone falls through to rule 12, not rule 5
        #expect(advise(makeCup([.sweetness: -1])).diagnosis.first == "Low sweetness.")
    }

    @Test func theExperimentCarriesItsTargetsEffectAndCriteria() throws {
        let experiment = try #require(advise(makeCup([.finish: -2, .sweetness: -1], drawdown: .slow)).experiment)
        #expect(experiment.targets == [.finish: -2, .sweetness: -1])
        #expect(experiment.toValue == 1.7)
        #expect(experiment.expectedEffect == "A faster drawdown; clearer and sweeter, with a longer finish")
        #expect(experiment.criteria.map(\.result) == ["Better", "Overshot: too far the other way", "No change", "Worse"])
        #expect(experiment.criteria[2].next == "Go back, and try: less agitation")
    }
}

@Suite struct DialInBlockedMoveTests {
    @Test func agitationAlreadyLowFallsBackToGrind() {
        var recipe = usualRecipe
        recipe.agitation = .low
        #expect(instruction(makeCup([.body: 1], recipe: recipe)) == "Grind coarser: Femobook A4Z 1.6 → 1.7")
    }

    @Test func unknownAgitationFallsBackToGrind() {
        var recipe = usualRecipe
        recipe.agitation = nil
        #expect(instruction(makeCup([.body: 1], recipe: recipe)) == "Grind coarser: Femobook A4Z 1.6 → 1.7")
    }

    @Test func temperatureAtTheTopFallsBackToGrind() {
        var recipe = usualRecipe
        recipe.brew.temperatureC = 99
        #expect(instruction(makeCup([.sweetness: -1], recipe: recipe)) == "Grind finer: Femobook A4Z 1.6 → 1.5")
    }

    @Test func temperatureAtTheBottomFallsBackToGrind() {
        var recipe = usualRecipe
        recipe.brew.temperatureC = 86
        #expect(instruction(makeCup([.acidity: 0], character: [.bitter], recipe: recipe)) == "Grind coarser: Femobook A4Z 1.6 → 1.7")
    }

    @Test func aBlockedVariableIsSkipped() {
        let context = DialInContext(grinder: a4z(), blocked: [.grind])
        #expect(instruction(makeCup([.finish: -2], drawdown: .slow), context) == "Less agitation: medium → low")
    }

    @Test func bothBlockedLeavesADiagnosisWithoutAnExperiment() {
        var recipe = usualRecipe
        recipe.agitation = .low
        let advice = advise(makeCup([.body: 1], recipe: recipe), DialInContext(grinder: a4z(), blocked: [.grind]))
        #expect(advice.next == .noSuggestion)
        #expect(advice.diagnosis == ["Body slightly high."])
    }
}

@Suite struct DialInGrindSizingTests {
    @Test func aStepSetByHandWins() {
        #expect(
            instruction(makeCup([.finish: -2], drawdown: .slow), DialInContext(grinder: a4z(step: 0.05))) == "Grind coarser: Femobook A4Z 1.6 → 1.65")
    }

    @Test func lowerIsCoarserOnSomeGrinders() {
        let context = DialInContext(grinder: a4z(higherIsCoarser: false))
        #expect(instruction(makeCup([.finish: -2], drawdown: .slow), context) == "Grind coarser: Femobook A4Z 1.6 → 1.5")
    }

    @Test func directionOnlyWithoutAKnownSetting() {
        var recipe = usualRecipe
        recipe.brew.grindSetting = nil
        #expect(instruction(makeCup([.finish: -2], drawdown: .slow, recipe: recipe)) == "Grind coarser by one step")
    }

    @Test func directionOnlyWithoutAStep() {
        let noStep = GrinderSetting(name: "Femobook A4Z", step: nil, higherIsCoarser: true, history: GrinderHistory(runs: []))
        #expect(instruction(makeCup([.finish: -2], drawdown: .slow), DialInContext(grinder: noStep)) == "Grind coarser by one step")
    }

    @Test func directionOnlyForAnUnusualSetting() {
        var recipe = usualRecipe
        recipe.brew.grindSetting = "4.5"
        #expect(instruction(makeCup([.finish: -2], drawdown: .slow, recipe: recipe)) == "Grind coarser by one step")
    }

    @Test func directionOnlyWhenTheGrinderIsntTheOneUsed() {
        var recipe = usualRecipe
        recipe.brew.grinder = "Fellow Ode 2"
        #expect(instruction(makeCup([.finish: -2], drawdown: .slow, recipe: recipe)) == "Grind coarser by one step")
    }

    @Test func grindKeepsTwoDecimals() {
        var recipe = usualRecipe
        recipe.brew.grindSetting = "1.65"
        #expect(instruction(makeCup([.finish: -2], drawdown: .slow, recipe: recipe)) == "Grind coarser: Femobook A4Z 1.65 → 1.75")
    }
}

@Suite struct DialInAdviceOutcomeTests {
    @Test func everythingOnTargetIsNothingToChange() {
        let advice = advise(makeCup([.acidity: 0, .sweetness: 0, .body: 0], drawdown: .normal))
        #expect(advice.next == .nothingToChange)
    }

    @Test func nothingRatedSaysSo() {
        #expect(advise(makeCup()).next == .nothingRated)
        #expect(DialInAdvisor.advise([], context: DialInContext()).next == .nothingRated)
    }

    @Test func notADialInMethod() {
        #expect(advise(makeCup([.sweetness: -1]), DialInContext(isDialInMethod: false)).next == .notADialInMethod)
    }

    @Test func theDiagnosisNamesWhatsOffAndAnOddDrawdown() {
        let advice = advise(makeCup([.sweetness: -1, .finish: -2, .acidity: 0], drawdown: .slow, character: [.muddy]))
        #expect(
            advice.diagnosis == [
                "A slow drawdown with low clarity, finish or sweetness.",
                "Sweetness slightly low, finish length much too low.",
                "Tasted muddy.",
                "The drawdown was slow.",
            ])
    }

    @Test func onlyTheLatestCupIsAdvisedOn() {
        let advice = DialInAdvisor.advise([makeCup([.body: 2]), makeCup([.body: 0])], context: DialInContext(grinder: a4z()))
        #expect(advice.next == .nothingToChange)
    }
}
