import Foundation

/// Reads one cup and suggests one change for the next. Pure: no database or
/// clock, so every rule is tested on Linux.
public enum DialInAdvisor {
    public static func advise(_ cup: CupTasting) -> DialInAdvice {
        guard !cup.isEmpty else { return DialInAdvice(diagnosis: [], next: .nothingRated) }
        var diagnosis = offTarget(cup) + drawdown(cup)
        if diagnosis.isEmpty { return DialInAdvice(diagnosis: ["Everything you rated is on target."], next: .nothingToChange) }

        let rated = RatedCup(tasting: cup)
        for rule in DialInRule.all where rule.matches(rated) {
            for move in [rule.primary, rule.alternate] where move.isOpen(for: cup) {
                if let pattern = rule.pattern { diagnosis.insert("\(pattern).", at: 0) }
                let suggestion = DialInSuggestion(
                    move: move, instruction: instruction(move, agitation: cup.agitation), expectedEffect: rule.effect,
                    criteria: criteria(move, rule: rule, cup: cup))
                return DialInAdvice(diagnosis: diagnosis, next: .change(suggestion))
            }
        }
        return DialInAdvice(diagnosis: diagnosis, next: .noSuggestion)
    }

    /// The move, with agitation's next level when the current one is known.
    private static func instruction(_ move: DialInMove, agitation: Agitation?) -> String {
        guard move.variable == .agitation, let agitation, let index = Agitation.allCases.firstIndex(of: agitation) else {
            return move.name
        }
        let next = Agitation.allCases[index + (move.direction == .up ? 1 : -1)]
        return "\(move.name): \(agitation.rawValue) → \(next.rawValue)"
    }

    /// The same four outcomes for every suggestion, naming its moves. With
    /// the rule's other move ruled out, a dead end sends the cup back here.
    private static func criteria(_ move: DialInMove, rule: DialInRule, cup: CupTasting) -> [DialInSuggestion.Criterion] {
        let alternate = rule.alternate == move ? rule.primary : rule.alternate
        let fallback =
            alternate.isOpen(for: cup)
            ? "Go back, and try: \(alternate.name.lowercased())"
            : "Go back, tick \(move.variable.name.lowercased()) as tried, and rate the cup again"
        return [
            .init(result: "Better", next: "\(move.name) by one more step"),
            .init(result: "Overshot: too far the other way", next: "Go halfway back and stay there"),
            .init(result: "No change", next: fallback),
            .init(result: "Worse", next: fallback),
        ]
    }

    /// "Sweetness slightly low, finish length much too low."
    private static func offTarget(_ cup: CupTasting) -> [String] {
        let off = SensoryAttribute.allCases.compactMap { attribute in
            cup.ratings[attribute].flatMap { $0 == 0 ? nil : "\(attribute.name.lowercased()) \(CupRating.label($0).lowercased())" }
        }
        let character = CharacterTag.allCases.filter(cup.character.contains).map(\.rawValue)
        var lines: [String] = []
        if !off.isEmpty { lines.append(sentence(off.joined(separator: ", "))) }
        if !character.isEmpty { lines.append(sentence("Tasted " + character.joined(separator: ", "))) }
        return lines
    }

    /// An abnormal drawdown, called out so it isn't hidden behind taste.
    private static func drawdown(_ cup: CupTasting) -> [String] {
        guard let drawdown = cup.drawdown, drawdown != .normal else { return [] }
        return ["The drawdown was \(drawdown.rawValue)."]
    }

    private static func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst() + "."
    }
}
