import Foundation

/// The cup a rule looks at. "Low" and "high" mean a rating at least one step
/// off; an unrated attribute is unknown, and never low, high, "not low" or
/// "not high".
struct RatedCup: Sendable {
    let tasting: CupTasting

    func low(_ attribute: SensoryAttribute) -> Bool { (tasting.ratings[attribute] ?? 0) <= -1 }
    func high(_ attribute: SensoryAttribute) -> Bool { (tasting.ratings[attribute] ?? 0) >= 1 }
    /// Rated, and on target or above.
    func notLow(_ attribute: SensoryAttribute) -> Bool { tasting.ratings[attribute].map { $0 >= 0 } ?? false }
    /// Rated, and on target or below.
    func notHigh(_ attribute: SensoryAttribute) -> Bool { tasting.ratings[attribute].map { $0 <= 0 } ?? false }
    func unknown(_ attribute: SensoryAttribute) -> Bool { tasting.ratings[attribute] == nil }
    func has(_ tag: CharacterTag) -> Bool { tasting.character.contains(tag) }
    /// No character tags: nothing tasted wrong, only too much or too little.
    var clean: Bool { tasting.character.isEmpty }
    var slow: Bool { tasting.drawdown == .slow }
    var fast: Bool { tasting.drawdown == .fast }
    /// Grind has been tried on this coffee and didn't help.
    var grindTried: Bool { tasting.tried.contains(.grind) }

    /// Every rated attribute other than `attribute` is on target.
    func othersOnTarget(_ attribute: SensoryAttribute) -> Bool {
        tasting.ratings.allSatisfy { $0.key == attribute || $0.value == 0 }
    }
}

/// A heuristic: when it applies, the change to try first, the one to try if
/// that's ruled out, what it should do, why, and how sure it is. Judgment
/// calls, not measured findings: tune them in DialInRuleTable, with a test.
struct DialInRule: Sendable {
    let id: Int
    let confidence: DialInConfidence
    let primary: DialInMove
    let alternate: DialInMove
    let effect: String
    let why: String
    let matches: @Sendable (RatedCup) -> Bool

    init(
        _ id: Int, _ confidence: DialInConfidence, _ primary: DialInMove, else alternate: DialInMove, effect: String, why: String,
        when matches: @escaping @Sendable (RatedCup) -> Bool
    ) {
        self.id = id
        self.confidence = confidence
        self.primary = primary
        self.alternate = alternate
        self.effect = effect
        self.why = why
        self.matches = matches
    }
}

extension DialInMove {
    static let finer = DialInMove(.grind, .up)
    static let coarser = DialInMove(.grind, .down)
    static let hotter = DialInMove(.temperature, .up)
    static let cooler = DialInMove(.temperature, .down)
    static let shorterRatio = DialInMove(.ratio, .up)
    static let longerRatio = DialInMove(.ratio, .down)
    static let moreAgitation = DialInMove(.agitation, .up)
    static let lessAgitation = DialInMove(.agitation, .down)
}
