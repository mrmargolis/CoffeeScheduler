import Foundation

/// What a dial-in suggestion changes.
public enum DialInVariable: String, CaseIterable, Sendable {
    case grind, temperature, ratio, agitation
}

/// Which way a suggestion moves its variable.
public enum DialInDirection: String, Sendable {
    /// Grind finer, hotter water, a shorter ratio (less water), more agitation.
    case up
    /// Grind coarser, cooler water, a longer ratio (more water), less agitation.
    case down
}

/// One change to try on the next cup.
public struct DialInMove: Hashable, Sendable {
    public let variable: DialInVariable
    public let direction: DialInDirection

    public init(_ variable: DialInVariable, _ direction: DialInDirection) {
        self.variable = variable
        self.direction = direction
    }

    /// "Grind finer", "Cooler water", "Shorter ratio", "Less agitation".
    public var name: String {
        switch (variable, direction) {
        case (.grind, .up): "Grind finer"
        case (.grind, .down): "Grind coarser"
        case (.temperature, .up): "Hotter water"
        case (.temperature, .down): "Cooler water"
        case (.ratio, .up): "Shorter ratio (less water)"
        case (.ratio, .down): "Longer ratio (more water)"
        case (.agitation, .up): "More agitation"
        case (.agitation, .down): "Less agitation"
        }
    }

    /// Whether it can be made from `agitation`: not less than low, or more
    /// than high. Every other move can always be made by a step.
    func isPossible(from agitation: Agitation?) -> Bool {
        guard variable == .agitation, let agitation else { return true }
        return direction == .up ? agitation != .high : agitation != .low
    }
}

/// The change to try next, what it should do, and what to do after.
public struct DialInSuggestion: Hashable, Sendable {
    public let move: DialInMove
    /// The move, with agitation's next level where the current one is known:
    /// "Grind coarser", "Less agitation: medium → low".
    public let instruction: String
    public let expectedEffect: String
    /// "If this happens, do that": the same four for every suggestion.
    public let criteria: [Criterion]

    public struct Criterion: Hashable, Sendable {
        public let result: String
        public let next: String
    }
}

/// What the advisor says about a cup.
public struct DialInAdvice: Hashable, Sendable {
    public enum Next: Hashable, Sendable {
        case change(DialInSuggestion)
        /// Everything rated is on target, with no character or flow problems.
        case nothingToChange
        /// Something is off, but no rule matched or its moves were ruled out.
        case noSuggestion
        /// Nothing was judged.
        case nothingRated
    }

    /// Short lines on what's off and why.
    public let diagnosis: [String]
    public let next: Next

    public var suggestion: DialInSuggestion? {
        if case .change(let suggestion) = next { return suggestion }
        return nil
    }
}
