import Foundation

/// Where a diverging cup chart draws each attribute, as fractions of the
/// track's width: −2 at the left edge, "ideal" in the middle, +2 at the
/// right. Shared by every chart, so cups compare on the same scale.
public enum CupChart {
    /// What a row shows.
    public enum Mark: Hashable, Sendable {
        /// Not evaluated: a marker at the centre, never shown as on target.
        case unknown
        /// On target: a marker at the centre.
        case onTarget
        /// Off target: a bar from the centre out to the rating.
        case bar(from: Double, to: Double)
    }

    public struct Row: Hashable, Sendable {
        public let attribute: SensoryAttribute
        public let value: Int?
        public let mark: Mark

        public var label: String { CupRating.label(value) }
    }

    /// The centre line, where "ideal" sits.
    public static let centre = 0.5

    /// The five stops' positions, left to right.
    public static let stops = CupRating.range.map(position)

    /// Where a rating sits along the track.
    public static func position(_ value: Int) -> Double {
        let clamped = min(CupRating.range.upperBound, max(CupRating.range.lowerBound, value))
        return Double(clamped - CupRating.range.lowerBound) / Double(CupRating.range.count - 1)
    }

    public static func mark(_ value: Int?) -> Mark {
        guard let value else { return .unknown }
        guard value != 0 else { return .onTarget }
        let end = position(value)
        return .bar(from: min(centre, end), to: max(centre, end))
    }

    /// One row per attribute, in the order they're rated.
    public static func rows(_ ratings: [SensoryAttribute: Int]) -> [Row] {
        SensoryAttribute.allCases.map { Row(attribute: $0, value: ratings[$0], mark: mark(ratings[$0])) }
    }
}
