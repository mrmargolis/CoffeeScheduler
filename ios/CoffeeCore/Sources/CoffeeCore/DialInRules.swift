import Foundation

/// The cup a rule looks at: its ratings, character and flow, with "low" and
/// "high" meaning a rating of at least one step off. An unrated attribute
/// is neither low, high, nor "not low".
struct RatedCup: Sendable {
    let evaluation: CupEvaluation

    func low(_ attribute: SensoryAttribute) -> Bool { (evaluation.ratings[attribute] ?? 0) <= -1 }
    func high(_ attribute: SensoryAttribute) -> Bool { (evaluation.ratings[attribute] ?? 0) >= 1 }
    /// Rated, and not below target.
    func notLow(_ attribute: SensoryAttribute) -> Bool { evaluation.ratings[attribute].map { $0 > -1 } ?? false }
    func has(_ tag: CharacterTag) -> Bool { evaluation.character[tag] != nil }
    var drawdown: Drawdown? { evaluation.drawdown }
    var flowProblem: Bool { evaluation.flowProblem }

    /// Every rated attribute other than `attribute` is on target.
    func othersOnTarget(_ attribute: SensoryAttribute) -> Bool {
        evaluation.ratings.allSatisfy { $0.key == attribute || $0.value == 0 }
    }
}

/// A diagnostic heuristic: a pattern in the cup, the change to try first,
/// a fallback, and what it should do. Hypotheses from the prototype, in
/// priority order; tune them here without touching storage or the UI.
struct DialInRule: Sendable {
    let pattern: String
    let matches: @Sendable (RatedCup) -> Bool
    let primary: DialInMove
    let alternate: DialInMove
    let targets: [SensoryAttribute]
    /// Character tags it should take away: gone on the next cup counts as better.
    var targetTags: [CharacterTag] = []
    let effect: String

    static let all: [DialInRule] = [
        DialInRule(
            pattern: "The bed stalled or channelled", matches: { $0.flowProblem },
            primary: .init(.agitation, .down), alternate: .init(.grind, .down),
            targets: [.clarity, .finish], effect: "A more even extraction: clearer, with a longer finish"),
        DialInRule(
            pattern: "A slow drawdown with low clarity, finish or sweetness",
            matches: { $0.drawdown == .slow && ($0.low(.clarity) || $0.low(.finish) || $0.low(.sweetness)) },
            primary: .init(.grind, .down), alternate: .init(.agitation, .down),
            targets: [.clarity, .finish, .sweetness], effect: "A faster drawdown; clearer and sweeter, with a longer finish"),
        DialInRule(
            pattern: "A fast drawdown with low intensity", matches: { $0.drawdown == .fast && $0.low(.intensity) },
            primary: .init(.grind, .up), alternate: .init(.ratio, .up),
            targets: [.intensity], effect: "More intensity"),
        DialInRule(
            pattern: "Intensity, sweetness and acidity all low",
            matches: { $0.low(.intensity) && $0.low(.sweetness) && $0.low(.acidity) },
            primary: .init(.grind, .up), alternate: .init(.temperature, .up),
            targets: [.intensity, .sweetness, .acidity], effect: "More extraction: more intensity, sweetness and acidity"),
        DialInRule(
            pattern: "Low sweetness with sharp acidity", matches: { $0.low(.sweetness) && $0.has(.sharp) },
            primary: .init(.grind, .up), alternate: .init(.temperature, .up),
            targets: [.sweetness], targetTags: [.sharp], effect: "Sweeter, and less sharp"),
        DialInRule(
            pattern: "Bitterness", matches: { $0.has(.bitter) },
            primary: .init(.temperature, .down), alternate: .init(.grind, .down),
            targets: [], targetTags: [.bitter], effect: "Less bitter"),
        DialInRule(
            pattern: "Muddy, or low clarity with enough intensity",
            matches: { $0.has(.muddy) || ($0.low(.clarity) && $0.notLow(.intensity)) },
            primary: .init(.agitation, .down), alternate: .init(.grind, .down),
            targets: [.clarity], targetTags: [.muddy], effect: "Clearer"),
        DialInRule(
            pattern: "Too much body", matches: { $0.high(.body) || $0.has(.heavy) },
            primary: .init(.agitation, .down), alternate: .init(.grind, .down),
            targets: [.body, .clarity], targetTags: [.heavy], effect: "Lighter and clearer"),
        DialInRule(
            pattern: "Low acidity with enough sweetness", matches: { $0.low(.acidity) && $0.notLow(.sweetness) },
            primary: .init(.grind, .down), alternate: .init(.temperature, .down),
            targets: [.acidity], effect: "Brighter"),
        DialInRule(
            pattern: "Low intensity in an otherwise good cup", matches: { $0.low(.intensity) && $0.othersOnTarget(.intensity) },
            primary: .init(.ratio, .up), alternate: .init(.grind, .up),
            targets: [.intensity], effect: "More intensity, the profile kept"),
        DialInRule(
            pattern: "Too intense", matches: { $0.high(.intensity) },
            primary: .init(.ratio, .down), alternate: .init(.grind, .down),
            targets: [.intensity], effect: "Less intense"),
        DialInRule(
            pattern: "Low sweetness", matches: { $0.low(.sweetness) },
            primary: .init(.temperature, .up), alternate: .init(.grind, .up),
            targets: [.sweetness], effect: "Sweeter"),
    ]
}
