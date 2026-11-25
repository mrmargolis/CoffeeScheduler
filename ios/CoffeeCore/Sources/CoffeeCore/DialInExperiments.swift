import Foundation

/// How an experiment turned out, decided by the next cup of the bag.
public enum ExperimentOutcome: String, CaseIterable, Sendable, Codable {
    /// Every target closer to ideal, or gone for a character tag.
    case improved
    /// No target further from ideal, but not all closer.
    case unchanged
    /// A target further from ideal.
    case worse
    /// Something else in the recipe changed too, so the result can't be
    /// put down to the experiment.
    case confounded
    /// Brewed on another grinder or with another method.
    case notComparable

    public var name: String {
        switch self {
        case .improved: "Improved"
        case .unchanged: "No change"
        case .worse: "Worse"
        case .confounded: "Other changes too"
        case .notComparable: "Not comparable"
        }
    }

    /// Whether it says something about the variable tested.
    public var isClean: Bool { self == .improved || self == .unchanged || self == .worse }
}

public enum ExperimentStatus: String, Sendable, Codable {
    case open, dismissed, superseded, decided
}

/// An experiment kept with a bag: what to try, the recipe it started from,
/// and, once the next cup decides it, how it went.
public struct SavedExperiment: Hashable, Sendable, Identifiable {
    public var id: String
    public var beanID: String
    /// The evaluation it was proposed after.
    public var createdFrom: String
    public var createdAt: Double
    public var start: CupRecipe
    public var experiment: DialInExperiment
    public var status: ExperimentStatus
    public var outcome: ExperimentOutcome?
    /// The evaluation that decided it.
    public var decidedBy: String?

    public init(
        id: String = UUID().uuidString, beanID: String, createdFrom: String, createdAt: Double, start: CupRecipe,
        experiment: DialInExperiment, status: ExperimentStatus = .open, outcome: ExperimentOutcome? = nil, decidedBy: String? = nil
    ) {
        self.id = id
        self.beanID = beanID
        self.createdFrom = createdFrom
        self.createdAt = createdAt
        self.start = start
        self.experiment = experiment
        self.status = status
        self.outcome = outcome
        self.decidedBy = decidedBy
    }

    /// The outcome `cup` gives this experiment, or nil when the cup didn't
    /// test it: the variable didn't move and nothing else changed either,
    /// so the experiment stays open.
    public func outcome(of cup: CupEvaluation) -> ExperimentOutcome? {
        let now = cup.recipe
        if differs(start.brew.grinder, now.brew.grinder) || differs(start.brew.method, now.brew.method) { return .notComparable }
        let variable = experiment.move.variable
        let moved = Self.measure(variable, start).flatMap { before in
            Self.measure(variable, now).map { after in (after - before) * Double(experiment.numberDirection) }
        }
        let others = DialInVariable.allCases.filter { $0 != variable }.contains { variable in
            Self.measure(variable, start).flatMap { before in Self.measure(variable, now).map { abs($0 - before) > 0.001 } } ?? false
        }
        let otherChanges = others || differs(start.brew.water, now.brew.water) || differs(start.brew.profile, now.brew.profile)
        guard let moved, moved > 0.001 else {
            // Not moved, or moved the wrong way: a wrong-way move is a different change
            return otherChanges || (moved ?? 0) < -0.001 ? .confounded : nil
        }
        return otherChanges ? .confounded : targetOutcome(cup)
    }

    /// Each target compared with where it started: closer to ideal (or on
    /// it, or a tag gone) is better; further is worse; unrated is no change.
    private func targetOutcome(_ cup: CupEvaluation) -> ExperimentOutcome {
        var results = experiment.targets.map { attribute, before -> Int in
            guard let after = cup.ratings[attribute] else { return 0 }
            if after == 0 || abs(after) < abs(before) { return 1 }
            return abs(after) > abs(before) ? -1 : 0
        }
        results += experiment.targetTags.map { cup.character[$0] == nil ? 1 : 0 }
        if results.contains(-1) { return .worse }
        return !results.isEmpty && results.allSatisfy { $0 == 1 } ? .improved : .unchanged
    }

    /// Both known and not the same.
    private func differs(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        return a.caseInsensitiveCompare(b) != .orderedSame
    }

    /// A variable as a number: the grind setting, °C, water per gram, or
    /// agitation's level.
    static func measure(_ variable: DialInVariable, _ recipe: CupRecipe) -> Double? {
        switch variable {
        case .grind: recipe.brew.grindValue
        case .temperature: recipe.brew.temperatureC
        case .ratio: recipe.brew.ratio.map { ($0 * 10).rounded() / 10 }
        case .agitation: recipe.agitation.flatMap { Agitation.allCases.firstIndex(of: $0) }.map(Double.init)
        }
    }
}

public enum DialInLimits {
    /// Grind is ruled out when the last two clean experiments on this grinder
    /// and method both changed grind and neither helped. Ones with other
    /// changes or on other gear don't count either way. `experiments` in any
    /// order.
    public static func blocked(_ experiments: [SavedExperiment], grinder: String?, method: String?) -> Set<DialInVariable> {
        let clean =
            experiments
            .filter { $0.status == .decided && ($0.outcome?.isClean ?? false) }
            .filter { same($0.start.brew.grinder, grinder) && same($0.start.brew.method, method) }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(2)
        let failedGrind = clean.count == 2 && clean.allSatisfy { $0.experiment.move.variable == .grind && $0.outcome != .improved }
        return failedGrind ? [.grind] : []
    }

    private static func same(_ a: String?, _ b: String?) -> Bool {
        (a ?? "").caseInsensitiveCompare(b ?? "") == .orderedSame
    }
}

extension DialInExperiment {
    /// An experiment the drinker chose instead of the suggestion: one move,
    /// optionally to a value they typed. It aims at everything off target on
    /// `cup` and any character tags it had.
    public static func custom(_ move: DialInMove, to typed: String?, after cup: CupEvaluation, grinder: GrinderSetting?) -> DialInExperiment {
        let to = typed?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let from = SavedExperiment.measure(move.variable, cup.recipe).map { value in
            switch move.variable {
            case .grind: cup.recipe.brew.grindSetting ?? DialInMove.grindNumber(value)
            case .temperature: "\(DialInMove.number(value)) °C"
            case .ratio: "1:\(DialInMove.number(value))"
            case .agitation: cup.recipe.agitation?.rawValue ?? ""
            }
        }
        return DialInExperiment(
            move: move, from: to == nil ? nil : from, to: to, toValue: to.flatMap { Double($0.filter { "0123456789.".contains($0) }) },
            targets: cup.ratings.filter { $0.value != 0 }, targetTags: Array(cup.character.keys).sorted { $0.rawValue < $1.rawValue },
            numberDirection: move.numberDirection(grinder: grinder), expectedEffect: "Closer to the cup you want",
            criteria: [
                .init(result: "Better", next: "\(move.name) by one more step"),
                .init(result: "No change or worse", next: "Go back, and try something else"),
            ])
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
