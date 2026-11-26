import Foundation

/// The cup a rule looks at: its ratings, character and flow, with "low" and
/// "high" meaning a rating of at least one step off. An unrated attribute
/// is neither low, high, nor "not low".
struct RatedCup: Sendable {
    let tasting: CupTasting

    func low(_ attribute: SensoryAttribute) -> Bool { (tasting.ratings[attribute] ?? 0) <= -1 }
    func high(_ attribute: SensoryAttribute) -> Bool { (tasting.ratings[attribute] ?? 0) >= 1 }
    /// Rated, and not below target.
    func notLow(_ attribute: SensoryAttribute) -> Bool { tasting.ratings[attribute].map { $0 > -1 } ?? false }
    func has(_ tag: CharacterTag) -> Bool { tasting.character.contains(tag) }
    var drawdown: Drawdown? { tasting.drawdown }

    /// Every rated attribute other than `attribute` is on target.
    func othersOnTarget(_ attribute: SensoryAttribute) -> Bool {
        tasting.ratings.allSatisfy { $0.key == attribute || $0.value == 0 }
    }
}

/// A diagnostic heuristic: a pattern in the cup, the change to try first,
/// a fallback, and what it should do. Hypotheses from the prototype, in
/// priority order; tune them here without touching the UI.
struct DialInRule: Sendable {
    /// What it saw, as a line of the diagnosis; nil when that would only
    /// repeat a single rating ("Low sweetness" after "Sweetness much too low").
    let pattern: String?
    let matches: @Sendable (RatedCup) -> Bool
    let primary: DialInMove
    let alternate: DialInMove
    let effect: String

    static let all: [DialInRule] = [
        DialInRule(
            pattern: "A slow drawdown with low clarity, finish or sweetness",
            matches: { $0.drawdown == .slow && ($0.low(.clarity) || $0.low(.finish) || $0.low(.sweetness)) },
            primary: .init(.grind, .down), alternate: .init(.agitation, .down), effect: "A faster drawdown; clearer and sweeter, with a longer finish"
        ),
        DialInRule(
            pattern: "A fast drawdown with low intensity", matches: { $0.drawdown == .fast && $0.low(.intensity) },
            primary: .init(.grind, .up), alternate: .init(.ratio, .up), effect: "More intensity"),
        DialInRule(
            pattern: "Intensity, sweetness and acidity all low",
            matches: { $0.low(.intensity) && $0.low(.sweetness) && $0.low(.acidity) },
            primary: .init(.grind, .up), alternate: .init(.temperature, .up), effect: "More extraction: more intensity, sweetness and acidity"),
        DialInRule(
            pattern: "Low sweetness with sharp acidity", matches: { $0.low(.sweetness) && $0.has(.sharp) },
            primary: .init(.grind, .up), alternate: .init(.temperature, .up), effect: "Sweeter, and less sharp"),
        DialInRule(
            pattern: nil, matches: { $0.has(.bitter) },
            primary: .init(.temperature, .down), alternate: .init(.grind, .down), effect: "Less bitter"),
        DialInRule(
            pattern: "Muddy, or low clarity with enough intensity",
            matches: { $0.has(.muddy) || ($0.low(.clarity) && $0.notLow(.intensity)) },
            primary: .init(.agitation, .down), alternate: .init(.grind, .down), effect: "Clearer"),
        DialInRule(
            pattern: nil, matches: { $0.high(.body) || $0.has(.heavy) },
            primary: .init(.agitation, .down), alternate: .init(.grind, .down), effect: "Lighter and clearer"),
        DialInRule(
            pattern: "Low acidity with enough sweetness", matches: { $0.low(.acidity) && $0.notLow(.sweetness) },
            primary: .init(.grind, .down), alternate: .init(.temperature, .down), effect: "Brighter"),
        DialInRule(
            pattern: "Low intensity in an otherwise good cup", matches: { $0.low(.intensity) && $0.othersOnTarget(.intensity) },
            primary: .init(.ratio, .up), alternate: .init(.grind, .up), effect: "More intensity, the profile kept"),
        DialInRule(
            pattern: nil, matches: { $0.high(.intensity) },
            primary: .init(.ratio, .down), alternate: .init(.grind, .down), effect: "Less intense"),
        DialInRule(
            pattern: nil, matches: { $0.low(.sweetness) },
            primary: .init(.temperature, .up), alternate: .init(.grind, .up), effect: "Sweeter"),
    ]
}
