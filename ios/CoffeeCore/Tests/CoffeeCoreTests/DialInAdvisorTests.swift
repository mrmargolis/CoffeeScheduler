import Foundation
import Testing

@testable import CoffeeCore

/// A cup from ratings in the order acidity, sweetness, intensity, clarity,
/// body, finish; nil is unrated.
private func cup(
    _ values: [Int?], drawdown: Drawdown? = nil, tags: Set<CharacterTag> = [], agitation: Agitation? = .medium,
    tried: Set<DialInVariable> = []
) -> CupTasting {
    let attributes: [SensoryAttribute] = [.acidity, .sweetness, .intensity, .clarity, .body, .finish]
    var ratings: [SensoryAttribute: Int] = [:]
    for (attribute, value) in zip(attributes, values) { ratings[attribute] = value }
    return CupTasting(ratings: ratings, drawdown: drawdown, character: tags, agitation: agitation, tried: tried)
}

private let none: [Int?] = [nil, nil, nil, nil, nil, nil]

/// What the advisor said, in the cases' terms: a move and its rule, or
/// "keep", "none" (no suggestion) or "ask" (nothing rated).
private func outcome(_ cup: CupTasting) -> String {
    let advice = DialInAdvisor.advise(cup)
    switch advice.next {
    case .change(let suggestion): return "\(suggestion.move.name) #\(suggestion.rule)"
    case .nothingToChange: return "keep"
    case .noSuggestion: return "none"
    case .nothingRated: return "ask"
    }
}

/// The reviewed rule set's own cases (1–30), with its expected move and rule.
@Suite struct DialInRuleCaseTests {
    @Test(arguments: [
        (1, cup(none, agitation: nil), "ask"),
        (2, cup([0, 0, 0, 0, 0, 0], drawdown: .slow, agitation: .high), "keep"),
        (3, cup([0, nil, 0, nil, nil, nil], drawdown: .fast, agitation: .low), "keep"),
        (4, cup([0, -1, 0, -1, 0, -2], drawdown: .slow), "Grind coarser #2"),
        (5, cup([0, -1, 0, -1, 0, -2], drawdown: .slow, tried: [.grind]), "Less agitation #2"),
        (6, cup([-1, -2, -2, nil, nil, nil], drawdown: .normal), "Grind finer #23"),
        (7, cup([0, -2, 0, 0, 0, 0], drawdown: .normal, tags: [.bitter]), "Cooler water #5"),
        (8, cup([0, -1, 0, 0, 2, 0], drawdown: .normal, tags: [.sharp, .heavy], agitation: .high), "Less agitation #3"),
        (9, cup([0, -1, 0, 0, 2, 0], drawdown: .normal, tags: [.sharp, .heavy], agitation: .low), "Grind coarser #3"),
        (10, cup([nil, nil, -2, -2, nil, nil], drawdown: .normal, tags: [.muddy], agitation: .high), "Less agitation #4"),
        (11, cup([1, -2, 0, nil, 0, nil], drawdown: .fast, tags: [.sharp]), "Grind finer #8"),
        (12, cup([1, -2, 0, nil, 0, nil], drawdown: .slow, tags: [.sharp]), "Less agitation #1"),
        (13, cup([0, 0, -2, 0, 0, 0], drawdown: .normal), "Shorter ratio (less water) #15"),
        (14, cup([0, 0, 2, 0, 0, 0], drawdown: .normal), "Longer ratio (more water) #16"),
        (15, cup([nil, nil, nil, -2, nil, nil]), "Less agitation #29"),
        (16, cup([nil, nil, nil, nil, -2, nil], drawdown: .normal), "Shorter ratio (less water) #21"),
        (17, cup([0, 0, 0, 0, 0, -2], drawdown: .normal), "Shorter ratio (less water) #41"),
        (18, cup([0, 0, 0, 0, 0, 2], drawdown: .normal), "Longer ratio (more water) #43"),
        (19, cup([2, 0, 0, 0, 0, 0], drawdown: .normal), "Longer ratio (more water) #34"),
        (20, cup([0, 0, 0, 0, 0, 0], drawdown: .normal, tags: [.sharp]), "Cooler water #13"),
        (21, cup([nil, -2, nil, nil, nil, nil], drawdown: .normal), "Hotter water #46"),
        (22, cup([nil, -2, nil, nil, nil, nil], drawdown: .normal, agitation: .high, tried: [.grind]), "Cooler water #22"),
        (23, cup([nil, -2, nil, nil, nil, nil], drawdown: .normal, agitation: .high, tried: [.grind, .temperature]), "Less agitation #22"),
        (24, cup([nil, -2, nil, nil, nil, nil], drawdown: .normal, agitation: .low, tried: [.grind, .temperature]), "none"),
        (25, cup([0, 0, -2, 0, 0, 0], drawdown: .normal, tried: [.ratio]), "Grind finer #15"),
        (26, cup([0, -2, 0, 0, 0, 0], drawdown: .normal, tags: [.bitter], tried: [.temperature, .grind]), "none"),
        (27, cup([0, 0, 0, 0, 0, 0], drawdown: .normal, tags: [.muddy], agitation: .low, tried: [.grind]), "none"),
        (28, cup([-2, 0, 0, 0, 0, 0], drawdown: .normal), "Grind coarser #27"),
        (29, cup([nil, nil, -2, nil, nil, nil], drawdown: .fast, agitation: .high, tried: [.grind]), "Shorter ratio (less water) #15"),
        (30, cup([-2, -2, -2, -2, -2, -2], drawdown: .normal, tried: [.grind, .temperature, .ratio, .agitation]), "none"),
    ])
    func reviewedCase(number: Int, cup: CupTasting, expected: String) {
        #expect(outcome(cup) == expected, "case \(number)")
    }

    /// The real coffee: plum and grape, not sweet or juicy, coarser was too
    /// delicate, finer didn't help; high agitation, grind ticked as tried.
    @Test func flatFruitAfterTryingGrindBothWays() throws {
        let advice = DialInAdvisor.advise(cup([nil, -2, nil, nil, nil, nil], agitation: .high, tried: [.grind]))
        let suggestion = try #require(advice.suggestion)
        #expect(suggestion.move == .cooler)
        #expect(suggestion.rule == 22)
        #expect(suggestion.confidence == .low)
        #expect(suggestion.expectedEffect == "More expressive fruit, and more apparent sweetness")
        #expect(suggestion.criteria[2].next == "Go back, and try: less agitation")
    }
}

@Suite struct DialInNewTagTests {
    @Test func dryingWithASlowDrawdownMeansLessAgitation() {
        #expect(outcome(cup([0, 0, 0, 0, 0, 0], drawdown: .slow, tags: [.drying])) == "Less agitation #101")
    }

    @Test func dryingAloneMeansCoarser() {
        #expect(outcome(cup([0, 0, 0, 0, 0, 0], tags: [.drying])) == "Grind coarser #102")
    }

    @Test func dryingIsAnsweredBeforeAFastDrawdownCallsForMoreExtraction() {
        #expect(outcome(cup([nil, -1, -1, nil, nil, nil], drawdown: .fast, tags: [.drying])) == "Grind coarser #102")
    }

    @Test func genericFruitAfterGrindMeansCooler() {
        #expect(outcome(cup([nil, -1, nil, nil, nil, nil], tags: [.genericFruit], tried: [.grind])) == "Cooler water #111")
    }

    @Test func genericFruitWithEnoughIntensityMeansLessAgitation() {
        #expect(outcome(cup([nil, nil, 0, nil, nil, nil], tags: [.genericFruit])) == "Less agitation #112")
    }

    @Test func genericFruitAloneMeansCooler() {
        #expect(outcome(cup(none, tags: [.genericFruit])) == "Cooler water #113")
    }
}

@Suite struct DialInEngineTests {
    @Test func aTriedVariableIsNeverSuggested() {
        for variable in DialInVariable.allCases {
            for values in [[0, -2, 0, 0, 0, 0], [nil, nil, -2, -1, nil, nil], [2, nil, 1, nil, 2, nil]] as [[Int?]] {
                let suggestion = DialInAdvisor.advise(cup(values, tried: [variable])).suggestion
                #expect(suggestion?.move.variable != variable)
            }
        }
    }

    @Test func agitationLimits() {
        #expect(DialInMove.lessAgitation.isPossible(from: .low) == false)
        #expect(DialInMove.moreAgitation.isPossible(from: .high) == false)
        #expect(DialInMove.lessAgitation.isPossible(from: nil))
        #expect(DialInMove.moreAgitation.isPossible(from: nil))
    }

    @Test func aKnownAgitationNamesTheNextLevel() {
        #expect(DialInAdvisor.advise(cup(none, tags: [.muddy], agitation: .medium)).suggestion?.instruction == "Less agitation: medium → low")
        #expect(DialInAdvisor.advise(cup(none, tags: [.muddy], agitation: nil)).suggestion?.instruction == "Less agitation")
    }

    @Test func aTagStopsKeepThisRecipe() {
        #expect(outcome(cup([0, 0, 0, 0, 0, 0], tags: [.heavy])) != "keep")
    }

    @Test func drawdownAloneIsNothingToAdviseOn() {
        #expect(outcome(cup(none, drawdown: .slow)) == "ask")
    }

    @Test func triedAloneIsNothingToAdviseOn() {
        #expect(outcome(cup(none, tried: [.grind])) == "ask")
    }

    @Test func aDefectWithItsChangesRuledOutDoesntFallThroughToMoreExtraction() {
        // Bitter and not sweet, cooler and coarser ruled out: not "hotter"
        #expect(outcome(cup([0, -2, 0, 0, 0, 0], tags: [.bitter], tried: [.temperature, .grind])) == "none")
    }

    @Test func everyRuleHasADistinctIdAndTwoVariables() {
        let ids = DialInRule.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(DialInRule.all.allSatisfy { $0.primary.variable != $0.alternate.variable })
    }
}

@Suite struct DialInWordingTests {
    @Test func theDiagnosisNamesWhatsOffTheTagsAndAnOddDrawdown() {
        let advice = DialInAdvisor.advise(cup([0, -1, nil, nil, nil, -2], drawdown: .slow, tags: [.muddy, .genericFruit]))
        #expect(
            advice.diagnosis == [
                "Sweetness slightly low, finish length much too low.", "Tasted muddy, generic fruit.", "The drawdown was slow.",
            ])
    }

    @Test func onTargetWithAnOddDrawdownSaysItsFine() {
        let advice = DialInAdvisor.advise(cup([0, 0, nil, nil, nil, nil], drawdown: .fast))
        #expect(
            advice.diagnosis == ["Everything you rated is on target.", "The drawdown was fast, but that's fine when the cup tastes right."])
    }

    @Test func theSuggestionCarriesWhyAndConfidence() throws {
        let suggestion = try #require(DialInAdvisor.advise(cup([0, 0, -2, 0, 0, 0])).suggestion)
        #expect(suggestion.confidence == .high)
        #expect(suggestion.why == "Less water makes a stronger cup without changing how it's extracted.")
        #expect(suggestion.criteria.map(\.result) == ["Better", "Overshot: too far the other way", "No change", "Worse"])
        #expect(suggestion.criteria[2].next == "Go back, and try: grind finer")
    }

    @Test func withTheAlternateRuledOutTheNoChangeStepSaysToTickIt() throws {
        let suggestion = try #require(DialInAdvisor.advise(cup([0, 0, -2, 0, 0, 0], tried: [.grind])).suggestion)
        #expect(suggestion.criteria[2].next == "Go back, tick ratio as tried, and rate the cup again")
    }
}
