import Foundation

/// A bag being put together from photos of its label and the roaster's web
/// page, and corrected by hand, before it's added to BeanConqueror. Any
/// field may be empty.
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

    public init() {}

    /// The roaster and coffee, for the searches.
    public var reading: BagLabel.Reading {
        get { BagLabel.Reading(roaster: roaster, coffee: coffee) }
        set {
            roaster = newValue.roaster
            coffee = newValue.coffee
        }
    }

    /// This draft with its empty fields filled from `other`: what's already
    /// here, read earlier or typed in, stays.
    public func filling(from other: BagDraft) -> BagDraft {
        var draft = self
        for field in Self.textFields where draft[keyPath: field].trimmingCharacters(in: .whitespaces).isEmpty {
            draft[keyPath: field] = other[keyPath: field]
        }
        draft.roastDate = roastDate ?? other.roastDate
        draft.weightGrams = weightGrams ?? other.weightGrams
        return draft
    }

    /// How many fields have something in them.
    public var filledCount: Int {
        Self.textFields.filter { !self[keyPath: $0].trimmingCharacters(in: .whitespaces).isEmpty }.count
            + (roastDate == nil ? 0 : 1) + (weightGrams == nil ? 0 : 1)
    }

    private static var textFields: [WritableKeyPath<BagDraft, String>] {
        [\.coffee, \.roaster, \.notes, \.country, \.region, \.producer, \.variety, \.process, \.url]
    }
}
