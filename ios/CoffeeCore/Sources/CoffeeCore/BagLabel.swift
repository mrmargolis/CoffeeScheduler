import Foundation

/// Picks a coffee's roaster and name out of the text read off a bag's label,
/// and builds the Bean Base search for them.
public enum BagLabel {
    /// One line of text found on the label.
    public struct Line: Equatable, Sendable {
        public var text: String
        /// The line's height as a fraction of the photo's: names are printed
        /// big, tasting notes and weights small.
        public var height: Double

        public init(_ text: String, height: Double) {
            self.text = text
            self.height = height
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
    }

    public static let searchPage = "https://www.loffeelabs.com/bean-base/search"

    /// Bean Base's search for the reading: its roaster filter, and its text
    /// search for the coffee. Nil when there's nothing to search for.
    ///
    /// Each filter is a numbered parameter, `f1=AND:roaster:Thankfully%20Coffee`,
    /// whose value is percent-encoded once inside it and then again as a
    /// whole: `f1=AND%3Aroaster%3AThankfully%2520Coffee`.
    public static func searchURL(for reading: Reading) -> URL? {
        let filters = [("roaster", reading.roaster), ("search", reading.coffee)]
            .map { ($0, $1.trimmingCharacters(in: .whitespaces)) }
            .filter { !$1.isEmpty }
        guard !filters.isEmpty else { return nil }
        let query = filters.enumerated().map { index, filter in
            "f\(index + 1)=" + encode("AND:\(filter.0):" + encode(filter.1))
        }
        return URL(string: searchPage + "?" + query.joined(separator: "&"))
    }

    /// Percent-encodes all but letters, digits and `-._~`, as JavaScript's
    /// encodeURIComponent does (bar its `!'()*`).
    private static func encode(_ text: String) -> String {
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    /// A best guess from the label's lines in reading order. A roaster the
    /// app already knows is matched by name; otherwise the biggest text is
    /// taken for the coffee and the next biggest for the roaster.
    public static func read(_ lines: [Line], knownRoasters: [String]) -> Reading {
        let candidates = lines.filter { isCandidate($0.text) }
        let roaster = knownRoaster(in: lines, from: knownRoasters)
        // The roaster's own line isn't the coffee's name
        let rest = candidates.filter { line in roaster.map { !contains(fold(line.text), fold($0)) } ?? true }
        let coffee = coffeeName(in: rest)
        let guessedRoaster = roaster ?? rest.filter { $0.text != coffee }.max { $0.height < $1.height }?.text
        return Reading(roaster: guessedRoaster ?? "", coffee: coffee ?? "")
    }

    /// The tallest line, joined to the line after it when that one is
    /// printed the same size: a long name wraps.
    private static func coffeeName(in lines: [Line]) -> String? {
        guard let index = lines.indices.max(by: { lines[$0].height < lines[$1].height }) else { return nil }
        let line = lines[index]
        let next = lines.index(after: index)
        if next < lines.endIndex, lines[next].height >= line.height * 0.85 {
            return "\(line.text) \(lines[next].text)"
        }
        return line.text
    }

    /// The longest known roaster named anywhere on the label.
    private static func knownRoaster(in lines: [Line], from roasters: [String]) -> String? {
        let text = fold(lines.map(\.text).joined(separator: " "))
        return roasters.filter { !$0.isEmpty && contains(text, fold($0)) }.max { $0.count < $1.count }
    }

    /// Whether a line could be a name rather than a weight, a date, a web
    /// address or a "Process: Washed" detail.
    static func isCandidate(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter).count
        guard letters >= 3, letters * 2 >= text.filter({ !$0.isWhitespace }).count else { return false }
        let folded = fold(text)
        if folded.contains(":") || folded.contains("www.") || folded.contains(".com") || folded.contains("@") { return false }
        let words = Set(folded.split { !$0.isLetter }.map(String.init))
        return words.isDisjoint(with: detailWords)
    }

    /// Words that mark a line as one of a label's details, not a name.
    private static let detailWords: Set<String> = [
        "roasted", "roast", "date", "net", "wt", "weight", "oz", "masl", "altitude", "elevation",
        "process", "varietal", "variety", "notes", "tasting", "harvest", "producer", "region", "best",
    ]

    /// Lowercased, without accents, so "Jijón" on the label matches "Jijon".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Whether `text` holds `word` as whole words, so "Onyx" doesn't match "Onyxa".
    private static func contains(_ text: String, _ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        var start = text.startIndex
        while let range = text.range(of: word, range: start..<text.endIndex) {
            let before = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
            let after = range.upperBound == text.endIndex || !text[range.upperBound].isLetter
            if before && after { return true }
            start = text.index(after: range.lowerBound)
        }
        return false
    }

    /// The prompt for the on-device language model, which reads the label
    /// better than `read` when the device has one.
    public static func prompt(for lines: [Line], knownRoasters: [String]) -> String {
        var prompt = """
            This is the text on a bag of coffee beans, one line at a time. Reply with exactly two lines, \
            "Roaster: " and the coffee roaster's name, then "Coffee: " and the coffee's name as printed. \
            Leave either blank if the text doesn't say.
            """
        if !knownRoasters.isEmpty {
            prompt += "\nRoasters the user has bought from before: \(knownRoasters.joined(separator: ", "))."
        }
        return prompt + "\n\n" + lines.map(\.text).joined(separator: "\n")
    }

    /// The roaster and coffee from the model's reply to `prompt`, or nil when
    /// it didn't answer in that form.
    public static func reading(fromModelAnswer answer: String) -> Reading? {
        var roaster: String?
        var coffee: String?
        for line in answer.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "")
            if let value = value(of: "roaster:", in: line) { roaster = value }
            if let value = value(of: "coffee:", in: line) { coffee = value }
        }
        guard roaster != nil || coffee != nil else { return nil }
        return Reading(roaster: roaster ?? "", coffee: coffee ?? "")
    }

    private static func value(of label: String, in line: String) -> String? {
        guard line.lowercased().hasPrefix(label) else { return nil }
        return line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
    }
}
