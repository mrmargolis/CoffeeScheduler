import Foundation

/// What one photo or page did to a draft: the fields it filled, the ones
/// it replaced (and what they held), and the guesses it stated again.
public struct BagFill: Equatable, Sendable {
    public struct Replacement: Equatable, Sendable {
        public let field: BagField
        /// What the field held before, as `BagDraft.value` gives it.
        public let old: String
    }

    public var filled: [BagField] = []
    public var replaced: [Replacement] = []
    public var confirmed: [BagField] = []

    /// Every field it touched.
    public var fields: [BagField] { filled + replaced.map(\.field) + confirmed }

    /// "Filled 2 fields, replaced 1 and confirmed 2 guesses from the page."
    public func summary(from source: String) -> String {
        var parts: [String] = []
        // The first count names what it counts; the others follow it
        if !filled.isEmpty { parts.append("filled \(Self.count(filled.count, "field"))") }
        if !replaced.isEmpty {
            parts.append("replaced " + (parts.isEmpty ? Self.count(replaced.count, "field") : "\(replaced.count)"))
        }
        if !confirmed.isEmpty { parts.append("confirmed \(Self.count(confirmed.count, "guess", "guesses"))") }
        guard let last = parts.popLast() else { return "Nothing new from \(source). Fill in the rest by hand." }
        let list = parts.isEmpty ? last : parts.joined(separator: ", ") + " and " + last
        return list.prefix(1).uppercased() + list.dropFirst() + " from \(source)."
    }

    private static func count(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) \(n == 1 ? one : many ?? one + "s")"
    }
}

extension BagDraft {
    /// This draft merged with `other`, and what that did.
    public func filling(with other: BagDraft) -> (draft: BagDraft, fill: BagFill) {
        let merged = merging(other)
        var fill = BagFill()
        for field in BagField.allCases {
            if merged.value(field) != value(field) {
                if let old = value(field), has(field) {
                    fill.replaced.append(.init(field: field, old: old))
                } else {
                    fill.filled.append(field)
                }
            } else if isGuess(field) && !merged.isGuess(field) {
                fill.confirmed.append(field)
            }
        }
        return (merged, fill)
    }

    /// How many of `fields` hold a value, and how many of those are guesses.
    public func count(_ fields: [BagField]) -> (filled: Int, guesses: Int) {
        (fields.count(where: has), fields.count(where: isGuess))
    }

    /// The origin in a line, for "Notes and origin" when it's folded:
    /// "Ethiopia · Guji · Natural · Hambela Estate · Heirloom".
    public var originLine: String {
        [country, region, process, producer, variety]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
