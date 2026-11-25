import Foundation

/// A sensory attribute of a cup, rated against the cup the drinker wants
/// rather than as a score.
public enum SensoryAttribute: String, CaseIterable, Sendable, Codable, CodingKeyRepresentable {
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

    /// "Much too low" … "Much too high", or "Not evaluated" for nil.
    public static func label(_ value: Int?) -> String {
        switch value {
        case nil: "Not evaluated"
        case -2: "Much too low"
        case -1: "Slightly low"
        case 0: "On target"
        case 1: "Slightly high"
        default: "Much too high"
        }
    }

    /// A stored value, clamped into range; nil stays nil.
    static func clamped(_ value: Int?) -> Int? {
        value.map { min(range.upperBound, max(range.lowerBound, $0)) }
    }
}

public enum Drawdown: String, CaseIterable, Sendable {
    case slow, normal, fast
}

public enum Agitation: String, CaseIterable, Sendable, Codable {
    case low, medium, high
}

/// What's wrong with a cup's character, as opposed to how much of an
/// attribute it has: acidity can be on target and still sharp.
public enum CharacterTag: String, CaseIterable, Sendable, Codable {
    case sharp, muddy, bitter, heavy
}

/// Who put a tag on a cup: the drinker, or the on-device model reading the
/// notes (a proposal until accepted).
public enum TagSource: String, Sendable {
    case user, model
}

/// How a cup compares with the last evaluated cup of the same bag, or that
/// the bag is dialed in: the recipe is right, so stop suggesting changes.
public enum Verdict: String, CaseIterable, Sendable {
    case better, same, worse
    case dialedIn = "dialed_in"
}

/// A cup's recipe as entered with an evaluation: what BeanConqueror records,
/// plus agitation, which it doesn't.
public struct CupRecipe: Hashable, Sendable, Codable {
    public var brew: BrewRecipe
    public var agitation: Agitation?

    public init(brew: BrewRecipe = BrewRecipe(), agitation: Agitation? = nil) {
        self.brew = brew
        self.agitation = agitation
    }
}

/// Feedback on one cup, recorded when the drinker wants advice on a bag.
public struct CupEvaluation: Hashable, Sendable, Identifiable {
    public var id: String
    public var beanID: String
    /// When the cup was evaluated, in seconds since 1970, for ordering and
    /// matching to a brew.
    public var timestamp: Double
    /// The local day of `timestamp`, YYYY-MM-DD.
    public var date: String
    public var recipe: CupRecipe
    /// Rated attributes only; one that's missing wasn't evaluated.
    public var ratings: [SensoryAttribute: Int]
    public var drawdown: Drawdown?
    /// The bed stalled or channelled.
    public var flowProblem: Bool
    public var verdict: Verdict?
    public var character: [CharacterTag: TagSource]
    /// Recognisable flavours, as typed: "stone fruit", "jasmine".
    public var flavours: [String]
    public var notes: String?
    /// The BeanConqueror brew it describes, once imported: linked by the
    /// store on import, or by hand.
    public var brewID: String?
    /// Linked, or left unlinked, by hand: imports keep it as it is.
    public var linkedByHand: Bool

    public init(
        id: String = UUID().uuidString, beanID: String, timestamp: Double, date: String, recipe: CupRecipe = CupRecipe(),
        ratings: [SensoryAttribute: Int] = [:], drawdown: Drawdown? = nil, flowProblem: Bool = false, verdict: Verdict? = nil,
        character: [CharacterTag: TagSource] = [:], flavours: [String] = [], notes: String? = nil, brewID: String? = nil,
        linkedByHand: Bool = false
    ) {
        self.id = id
        self.beanID = beanID
        self.timestamp = timestamp
        self.date = date
        self.recipe = recipe
        self.ratings = ratings
        self.drawdown = drawdown
        self.flowProblem = flowProblem
        self.verdict = verdict
        self.character = character
        self.flavours = flavours
        self.notes = notes
        self.brewID = brewID
        self.linkedByHand = linkedByHand
    }

    /// A new evaluation of a bag at `time`, starting from `recipe` with
    /// nothing rated.
    public static func new(beanID: String, at time: Date, timeZone: TimeZone = .current, recipe: CupRecipe) -> CupEvaluation {
        CupEvaluation(
            beanID: beanID, timestamp: time.timeIntervalSince1970, date: DateUtils.isoString(time, timeZone: timeZone), recipe: recipe)
    }
}

extension CupRecipe {
    /// What changed from `previous`, one phrase per field: "Grind 1.6 → 1.7",
    /// "Agitation medium → low". A field that's unknown shows as "?".
    public func changes(from previous: CupRecipe) -> [String] {
        let old = previous.brew
        let new = brew
        let number = { (value: Double?) in value.map(BrewRecipe.number) }
        let fields = [
            Field(name: "Grinder", before: old.grinder, after: new.grinder),
            Field(name: "Grind", before: old.grindSetting, after: new.grindSetting),
            Field(name: "Temperature", before: number(old.temperatureC), after: number(new.temperatureC), unit: " °C"),
            Field(name: "Dose", before: number(old.doseGrams), after: number(new.doseGrams), unit: " g"),
            Field(name: "Water", before: number(old.waterGrams), after: number(new.waterGrams), unit: " g"),
            Field(name: "Agitation", before: previous.agitation?.rawValue, after: agitation?.rawValue),
            Field(name: "Method", before: old.method, after: new.method),
            Field(name: "Water recipe", before: old.water, after: new.water),
            Field(name: "Profile", before: old.profile, after: new.profile),
        ]
        return fields.compactMap(\.change)
    }

    /// One field of the recipe, before and after.
    private struct Field {
        var name: String
        var before: String?
        var after: String?
        var unit = ""

        var change: String? {
            guard before != after else { return nil }
            return "\(name) \(before ?? "?") → \(after ?? "?")\(after == nil ? "" : unit)"
        }
    }
}
