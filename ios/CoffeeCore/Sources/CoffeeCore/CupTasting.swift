import Foundation

/// A sensory attribute of a cup, rated against the cup the drinker wants
/// rather than as a score.
public enum SensoryAttribute: String, CaseIterable, Sendable {
    case acidity, sweetness, intensity, clarity, body, finish

    public var name: String {
        switch self {
        case .acidity: "Acidity"
        case .sweetness: "Sweetness"
        case .intensity: "Flavour intensity"
        case .clarity: "Clarity"
        case .body: "Body"
        case .finish: "Finish length"
        }
    }
}

/// How far an attribute is from what's wanted: −2 much too low … +2 much
/// too high. Neither direction is better; distance from 0 is the problem.
public enum CupRating {
    public static let range = -2...2

    /// "Much too low" … "Much too high", or "Not rated" for nil.
    public static func label(_ value: Int?) -> String {
        switch value {
        case nil: "Not rated"
        case -2: "Much too low"
        case -1: "Slightly low"
        case 0: "On target"
        case 1: "Slightly high"
        default: "Much too high"
        }
    }
}

public enum Drawdown: String, CaseIterable, Sendable {
    case slow, normal, fast
}

public enum Agitation: String, CaseIterable, Sendable {
    case low, medium, high
}

/// What's wrong with a cup's character, as opposed to how much of an
/// attribute it has: acidity can be on target and still sharp.
public enum CharacterTag: String, CaseIterable, Sendable {
    case sharp, muddy, bitter, heavy
}

/// One cup as the drinker judged it, to advise on. Nothing is kept: the
/// tool reads a cup and suggests the next change.
public struct CupTasting: Hashable, Sendable {
    /// Rated attributes only; one that's missing wasn't judged.
    public var ratings: [SensoryAttribute: Int]
    public var drawdown: Drawdown?
    /// The bed stalled or channelled.
    public var flowProblem: Bool
    public var character: Set<CharacterTag>
    /// How much agitation the cup had, if given: rules out suggesting less
    /// at low, or more at high.
    public var agitation: Agitation?

    public init(
        ratings: [SensoryAttribute: Int] = [:], drawdown: Drawdown? = nil, flowProblem: Bool = false,
        character: Set<CharacterTag> = [], agitation: Agitation? = nil
    ) {
        self.ratings = ratings
        self.drawdown = drawdown
        self.flowProblem = flowProblem
        self.character = character
        self.agitation = agitation
    }

    /// Nothing judged yet: no rating, drawdown, flow problem or tag.
    public var isEmpty: Bool {
        ratings.isEmpty && drawdown == nil && !flowProblem && character.isEmpty
    }
}
