import Foundation

/// Reading a shop's heading for a coffee, which often adds its origin,
/// variety, process and bag size to the name: "Kenya Gachatha AB
/// Washed(2026)", "Ayele Tulu - Bare Station - White Honey Process Landrace
/// Ethiopia - 120g".
extension BagLabel {
    /// The coffee's name: the heading's parts (split at "|", " - " and the
    /// like) that are names, each without a country in front or the details
    /// after it, and without sizes and bracketed asides ("(Extra-light)").
    static func coffeeName(inHeading heading: String) -> String {
        guard let firstLine = heading.split(whereSeparator: \.isNewline).first else { return "" }
        let text = String(firstLine).replacingOccurrences(of: #"\s*\([^)]*\)"#, with: " ", options: .regularExpression)
        let parts = headingParts(text)
        let named = parts.map(withoutLeadingCountry).filter { !startsWithDetail($0) }.map(upToDetails)
        let name = named.isEmpty ? parts.first ?? "" : named.joined(separator: " ")
        return tidy(name, name: true)
    }

    /// The country, variety and process a heading names, as stated: it's
    /// the shop's own name for the coffee.
    static func details(inHeading heading: String) -> BagDraft {
        var draft = BagDraft()
        draft.country = names(in: heading, from: countries).first ?? ""
        draft.variety = names(in: heading, from: varieties).joined(separator: ", ")
        draft.process = process(in: heading) ?? ""
        for field in BagField.allCases where draft.has(field) {
            draft.certainty[field] = .stated
        }
        return draft
    }

    /// The parts between separators, without sizes.
    private static func headingParts(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "|–—·")).flatMap { $0.components(separatedBy: " - ") }
            .map { part in
                part.replacingOccurrences(of: #"(?i)\b\d+(?:[.,]\d+)?\s*(?:kg|g|oz|lbs?)\b"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-,")))
            }
            .filter { !$0.isEmpty }
    }

    /// "Habtamu Fekadu" from "Ethiopia Habtamu Fekadu"; a part that's only a
    /// country and details is left alone.
    private static func withoutLeadingCountry(_ text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1, let length = countryLength(at: 0, in: words.map(token)) else { return text }
        let rest = words.dropFirst(length)
        return startsWithDetail(rest.joined(separator: " ")) || rest.isEmpty ? text : rest.joined(separator: " ")
    }

    private static func startsWithDetail(_ text: String) -> Bool {
        detailLength(at: 0, in: text.split(separator: " ").map { token(String($0)) }) > 0
    }

    /// The words before the first origin, variety or process after the
    /// first word: "Gachatha AB" from "Gachatha AB Washed".
    private static func upToDetails(_ text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        let tokens = words.map(token)
        guard let end = tokens.indices.dropFirst().first(where: { detailLength(at: $0, in: tokens) > 0 }) else { return text }
        return words[..<end].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",-"))
    }

    /// A word folded and without punctuation, for matching: "agaro," is "agaro".
    private static func token(_ word: String) -> String {
        fold(word).filter { $0.isLetter || $0.isNumber }
    }

    /// How many words from `start` make a country's name, if they do.
    private static func countryLength(at start: Int, in tokens: [String]) -> Int? {
        phraseLength(at: start, in: tokens, from: countries)
    }

    /// How many words from `start` make an origin, variety, process or roast,
    /// or 0: "pink bourbon", "white honey", "washed".
    private static func detailLength(at start: Int, in tokens: [String]) -> Int {
        if let length = phraseLength(at: start, in: tokens, from: countries + regions + varieties) { return length }
        var end = start
        while end < tokens.count, processQualifiers.contains(tokens[end]) { end += 1 }
        if end < tokens.count, processWords.contains(tokens[end]) || headingWords.contains(tokens[end]) { return end - start + 1 }
        return 0
    }

    /// Words a heading adds that aren't the name.
    private static var headingWords: Set<String> {
        ["process", "processed", "light", "medium", "dark", "roast", "espresso", "filter", "omni", "extralight", "ultralight"]
    }

    private static func phraseLength(at start: Int, in tokens: [String], from list: [Name]) -> Int? {
        let phrases = list.flatMap { [fold($0.name)] + $0.spellings }.map { $0.split(separator: " ").map { token(String($0)) } }
        return phrases.filter { phrase in
            start + phrase.count <= tokens.count && Array(tokens[start..<(start + phrase.count)]) == phrase
        }
        .map(\.count).max()
    }
}
