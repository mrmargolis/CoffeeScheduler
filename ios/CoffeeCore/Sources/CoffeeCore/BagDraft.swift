import Foundation

/// A bag being put together from photos of its label, pages about it, and
/// what's typed in, before it's added to BeanConqueror. Any field may be
/// empty. Each value remembers how sure it is, so a later source replaces
/// a guess but not something stated or typed.
public struct BagDraft: Equatable, Sendable {
    public var coffee = ""
    public var roaster = ""
    /// The roast date, `YYYY-MM-DD`.
    public var roastDate: String?
    public var weightGrams: Int?
    public var notes = ""
    public var country = ""
    public var region = ""
    public var producer = ""
    public var variety = ""
    public var process = ""
    /// The roaster's page for the coffee.
    public var url = ""
    /// How sure each field's value is; a field not here is a guess.
    public var certainty: [BagField: Certainty] = [:]

    public init() {}

    /// The roaster and coffee, for the searches.
    public var reading: BagLabel.Reading {
        BagLabel.Reading(roaster: roaster, coffee: coffee)
    }

    /// Takes the roaster and coffee read off a label, guesses but for a
    /// roaster the app already knows.
    public mutating func take(_ reading: BagLabel.Reading, knownRoasters: [String]) {
        coffee = reading.coffee
        roaster = reading.roaster
        if knownRoasters.contains(reading.roaster) { certainty[.roaster] = .stated }
    }

    /// Sets a text field to what was typed or picked by hand, which nothing
    /// read later replaces.
    public mutating func type(_ text: String, in field: BagField) {
        guard let path = field.text else { return }
        self[keyPath: path] = text
        certainty[field] = .typed
    }

    /// This draft with `other`'s values where they're better: in a field
    /// that's empty, or stated where this one is only guessed or stated
    /// differently. A guess never replaces a value, a blank never clears
    /// one, and nothing replaces what was typed.
    public func merging(_ other: BagDraft) -> BagDraft {
        var draft = self
        for field in BagField.allCases where other.has(field) {
            let new = other.certainty[field] ?? .guessed
            let old = certainty[field] ?? .guessed
            let better = new == .stated && old != .typed && other.value(field) != value(field)
            guard !has(field) || better else { continue }
            draft.copy(field, from: other)
            draft.certainty[field] = new
        }
        return draft
    }

    /// How many fields `other`, merged into this draft, filled and how many
    /// it changed.
    public func changes(to other: BagDraft) -> (filled: Int, replaced: Int) {
        let changed = BagField.allCases.filter { other.value($0) != value($0) && other.has($0) }
        let filled = changed.filter { !has($0) }.count
        return (filled, changed.count - filled)
    }

    /// Whether the field holds a guess: worth checking before adding.
    public func isGuess(_ field: BagField) -> Bool {
        has(field) && (certainty[field] ?? .guessed) == .guessed
    }

    public func has(_ field: BagField) -> Bool {
        !(value(field) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The field's value as text, for comparing.
    private func value(_ field: BagField) -> String? {
        switch field {
        case .roastDate: roastDate
        case .weight: weightGrams.map(String.init)
        default: field.text.map { self[keyPath: $0] }
        }
    }

    mutating func clear(_ field: BagField) {
        copy(field, from: BagDraft())
        certainty[field] = nil
    }

    private mutating func copy(_ field: BagField, from other: BagDraft) {
        switch field {
        case .roastDate: roastDate = other.roastDate
        case .weight: weightGrams = other.weightGrams
        default: if let path = field.text { self[keyPath: path] = other[keyPath: path] }
        }
    }
}

/// A field of a `BagDraft`.
public enum BagField: CaseIterable, Sendable {
    case coffee, roaster, roastDate, weight, notes, country, region, producer, variety, process, url

    /// The text field's key path; nil for the roast date and weight.
    public var text: WritableKeyPath<BagDraft, String>? {
        switch self {
        case .coffee: \.coffee
        case .roaster: \.roaster
        case .notes: \.notes
        case .country: \.country
        case .region: \.region
        case .producer: \.producer
        case .variety: \.variety
        case .process: \.process
        case .url: \.url
        case .roastDate, .weight: nil
        }
    }
}

/// How sure a value in a `BagDraft` is.
public enum Certainty: Int, Comparable, Sendable {
    /// Picked out by its place on the label or its words.
    case guessed
    /// Labelled as what it is ("Process: Washed"), a roaster the app knows,
    /// or from the coffee's own page.
    case stated
    /// Typed or picked by hand.
    case typed

    public static func < (lhs: Certainty, rhs: Certainty) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
