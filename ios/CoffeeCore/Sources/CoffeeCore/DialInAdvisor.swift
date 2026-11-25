import Foundation

/// Reads a bag's latest cup and proposes one change for the next. Pure: no
/// database or clock, so every rule is tested on Linux.
public enum DialInAdvisor {
    /// `evaluations` oldest first; the last is the cup to advise on.
    public static func advise(_ evaluations: [CupEvaluation], context: DialInContext) -> DialInAdvice {
        guard let latest = evaluations.last else { return DialInAdvice(diagnosis: [], next: .nothingRated) }
        let cup = RatedCup(evaluation: latest)
        var diagnosis = Self.offTarget(latest) + Self.flow(latest)
        guard context.isDialInMethod else { return DialInAdvice(diagnosis: diagnosis, next: .notADialInMethod) }
        if latest.verdict == .dialedIn { return DialInAdvice(diagnosis: diagnosis, next: .dialedIn) }
        if latest.ratings.isEmpty && latest.character.isEmpty && !latest.flowProblem && latest.drawdown == nil {
            return DialInAdvice(diagnosis: [], next: .nothingRated)
        }
        if diagnosis.isEmpty { return DialInAdvice(diagnosis: ["Everything you rated is on target."], next: .nothingToChange) }

        for rule in DialInRule.all where rule.matches(cup) {
            for move in [rule.primary, rule.alternate] {
                guard let planned = move.plan(for: latest.recipe, in: context) else { continue }
                diagnosis.insert("\(rule.pattern).", at: 0)
                let experiment = experiment(move, planned, rule: rule, cup: latest, grinder: context.grinder)
                return DialInAdvice(diagnosis: diagnosis, next: .experiment(experiment))
            }
        }
        return DialInAdvice(diagnosis: diagnosis, next: .noSuggestion)
    }

    private static func experiment(
        _ move: DialInMove, _ planned: PlannedMove, rule: DialInRule, cup: CupEvaluation, grinder: GrinderSetting?
    ) -> DialInExperiment {
        var targets: [SensoryAttribute: Int] = [:]
        for attribute in rule.targets { targets[attribute] = cup.ratings[attribute] }
        return DialInExperiment(
            move: move, from: planned.from, to: planned.to, toValue: planned.toValue, targets: targets,
            targetTags: rule.targetTags.filter { cup.character[$0] != nil }, numberDirection: move.numberDirection(grinder: grinder),
            expectedEffect: rule.effect, criteria: criteria(move, rule: rule))
    }

    /// The same four outcomes for every experiment, naming its moves.
    private static func criteria(_ move: DialInMove, rule: DialInRule) -> [DialInExperiment.Criterion] {
        let alternate = rule.alternate == move ? rule.primary : rule.alternate
        return [
            .init(result: "Better", next: "\(move.name) by one more step"),
            .init(result: "Overshot: too far the other way", next: "Go halfway back and stay there"),
            .init(result: "No change", next: "Go back, and try: \(alternate.name.lowercased())"),
            .init(result: "Worse", next: "Go back, and try: \(alternate.name.lowercased())"),
        ]
    }

    /// "Sweetness slightly low, finish length much too low."
    private static func offTarget(_ cup: CupEvaluation) -> [String] {
        let off = SensoryAttribute.allCases.compactMap { attribute in
            cup.ratings[attribute].flatMap { $0 == 0 ? nil : "\(attribute.name.lowercased()) \(CupRating.label($0).lowercased())" }
        }
        let character = CharacterTag.allCases.filter { cup.character[$0] != nil }.map(\.rawValue)
        var lines: [String] = []
        if !off.isEmpty { lines.append(sentence(off.joined(separator: ", "))) }
        if !character.isEmpty { lines.append(sentence("Tasted " + character.joined(separator: ", "))) }
        return lines
    }

    /// An abnormal drawdown or bed, called out so it isn't hidden behind taste.
    private static func flow(_ cup: CupEvaluation) -> [String] {
        var lines: [String] = []
        if cup.flowProblem { lines.append("The bed stalled or channelled.") }
        if let drawdown = cup.drawdown, drawdown != .normal { lines.append("The drawdown was \(drawdown.rawValue).") }
        return lines
    }

    private static func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst() + "."
    }
}
