import Foundation

/// What a dial-in experiment changes.
public enum DialInVariable: String, CaseIterable, Sendable, Codable {
    case grind, temperature, ratio, agitation
}

/// Which way an experiment moves its variable.
public enum DialInDirection: String, Sendable, Codable {
    /// Grind finer, hotter water, a shorter ratio (less water), more agitation.
    case up
    /// Grind coarser, cooler water, a longer ratio (more water), less agitation.
    case down
}

/// One change to try on the next cup.
public struct DialInMove: Hashable, Sendable, Codable {
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
        case (.ratio, .up): "Shorter ratio"
        case (.ratio, .down): "Longer ratio"
        case (.agitation, .up): "More agitation"
        case (.agitation, .down): "Less agitation"
        }
    }
}

/// The next cup's one change, with what to expect and what to do after.
public struct DialInExperiment: Hashable, Sendable, Codable {
    public let move: DialInMove
    /// The value now and the value to try, as shown: "1.6" → "1.7". Nil
    /// when only the direction is known.
    public let from: String?
    public let to: String?
    /// The same as numbers where they are numbers, for checking the next cup.
    public let toValue: Double?
    /// The attributes it's meant to move, with their ratings on this cup.
    public let targets: [SensoryAttribute: Int]
    /// Character tags on this cup it's meant to take away.
    public let targetTags: [CharacterTag]
    /// Which way the variable's number should go: +1 up, −1 down. Grind is
    /// its setting, temperature °C, ratio water per gram, agitation its level.
    public let numberDirection: Int
    public let expectedEffect: String
    /// "If this happens, do that": the same four for every experiment.
    public let criteria: [Criterion]

    public struct Criterion: Hashable, Sendable, Codable {
        public let result: String
        public let next: String
    }

    /// One line: "Grind coarser: Femobook A4Z 1.6 → 1.7", or "Grind coarser by one step".
    public var instruction: String {
        guard let from, let to else { return "\(move.name) by one step" }
        return "\(move.name): \(from) → \(to)"
    }
}

/// What the advisor says about the latest cup.
public struct DialInAdvice: Hashable, Sendable {
    public enum Next: Hashable, Sendable {
        case experiment(DialInExperiment)
        /// Everything rated is on target, with no character or flow problems.
        case nothingToChange
        /// Something is off, but no rule matched or every change was blocked.
        case noSuggestion
        /// The cup was brewed with a method that doesn't get dial-in advice.
        case notADialInMethod
        /// Nothing was rated.
        case nothingRated
    }

    /// Short lines on what's off and why.
    public let diagnosis: [String]
    public let next: Next

    public var experiment: DialInExperiment? {
        if case .experiment(let experiment) = next { return experiment }
        return nil
    }
}

/// What the advisor needs besides the cups: how to size each change.
public struct DialInContext: Sendable {
    public var grinder: GrinderSetting?
    public var temperatureStep: Double
    public var isDialInMethod: Bool
    /// Variables not to suggest, e.g. grind after two experiments that
    /// didn't help.
    public var blocked: Set<DialInVariable>

    public init(
        grinder: GrinderSetting? = nil, temperatureStep: Double = 2, isDialInMethod: Bool = true, blocked: Set<DialInVariable> = []
    ) {
        self.grinder = grinder
        self.temperatureStep = temperatureStep
        self.isDialInMethod = isDialInMethod
        self.blocked = blocked
    }
}
