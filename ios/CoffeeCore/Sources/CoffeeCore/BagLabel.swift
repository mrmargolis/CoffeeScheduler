import Foundation

/// Picks a coffee's roaster and name out of the text read off a bag's label,
/// and builds the Bean Base search for them.
///
/// Labels share a layout: the roaster's logo is often the biggest text, with
/// "Coffee Roasters" or "Coffee Co." under it; the coffee's name is the
/// biggest of the rest; and around it are lists of tasting notes, origins,
/// varieties and processes, which are never the name.
public enum BagLabel {
    /// One line of text found on the label, with where it sits in the photo
    /// as fractions of the photo's size, measured from the bottom left as
    /// Vision does.
    public struct Line: Equatable, Sendable {
        public var text: String
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(_ text: String, x: Double, y: Double, width: Double, height: Double) {
            self.text = text
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var top: Double { y + height }

        /// Whether the two lines share some of the photo's width.
        func overlapsHorizontally(_ other: Line) -> Bool {
            x < other.x + other.width && other.x < x + width
        }
    }

    /// The roaster and coffee to search for. Either may be empty.
    public struct Reading: Equatable, Sendable {
        public var roaster: String
        public var coffee: String

        public init(roaster: String, coffee: String) {
            self.roaster = roaster
            self.coffee = coffee
        }

        /// Both in title case where the label prints them all in capitals or
        /// all in lowercase.
        public var tidied: Reading {
            Reading(roaster: BagLabel.tidy(roaster, name: true), coffee: BagLabel.tidy(coffee, name: true))
        }
    }

    public static let searchPage = "https://www.loffeelabs.com/bean-base/search"

    /// Bean Base's search for the reading: its roaster filter, given the
    /// roaster's `searchName`, and its text search for the coffee. Nil when
    /// there's nothing to search for.
    ///
    /// Each filter is a numbered parameter, `f1=AND:roaster:Thankfully%20Coffee`,
    /// whose value is percent-encoded once inside it and then again as a
    /// whole: `f1=AND%3Aroaster%3AThankfully%2520Coffee`.
    public static func searchURL(for reading: Reading) -> URL? {
        let filters = [("roaster", searchName(reading.roaster)), ("search", reading.coffee)]
            .map { ($0, $1.trimmingCharacters(in: .whitespaces)) }
            .filter { !$1.isEmpty }
        guard !filters.isEmpty else { return nil }
        let query = filters.enumerated().map { index, filter in
            "f\(index + 1)=" + encode("AND:\(filter.0):" + encode(filter.1))
        }
        return URL(string: searchPage + "?" + query.joined(separator: "&"))
    }

    public static let googlePage = "https://www.google.com/search"

    /// A Google search for the roaster's full name and the coffee, for a
    /// coffee Bean Base doesn't have. Nil when there's nothing to search for.
    public static func googleURL(for reading: Reading) -> URL? {
        let terms = [reading.roaster, reading.coffee]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        return URL(string: googlePage + "?q=" + encode(terms.joined(separator: " ")))
    }

    /// Percent-encodes all but letters, digits and `-._~`, as JavaScript's
    /// encodeURIComponent does (bar its `!'()*`).
    private static func encode(_ text: String) -> String {
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    /// A best guess at the roaster and coffee from the label's lines. A
    /// roaster the app already knows is given by its name in the app.
    public static func read(_ lines: [Line], knownRoasters: [String]) -> Reading {
        let roaster = roaster(in: lines, knownRoasters: knownRoasters)
        let candidates = lines.indices.compactMap { index -> Line? in
            roaster.lines.contains(index) ? nil : nameCandidate(lines[index])
        }
        return Reading(roaster: roaster.name ?? "", coffee: coffeeName(in: candidates) ?? "")
    }

    /// The biggest line (the highest of those near enough the same size),
    /// joined to the line just under it when that's printed the same size:
    /// a long name wraps.
    private static func coffeeName(in lines: [Line]) -> String? {
        guard let tallest = lines.map(\.height).max(),
            let name = lines.filter({ $0.height >= tallest * 0.9 }).max(by: { $0.top < $1.top })
        else { return nil }
        let wrapped = lines.filter { line in
            line != name && line.top <= name.y + name.height * 0.5 && line.top >= name.y - name.height * 0.8
                && line.height >= name.height * 0.85 && line.overlapsHorizontally(name)
        }
        .max { $0.top < $1.top }
        return [name, wrapped].compactMap { $0?.text }.joined(separator: " ")
    }
}
