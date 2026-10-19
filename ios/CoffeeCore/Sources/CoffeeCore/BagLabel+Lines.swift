import Foundation

extension BagLabel {
    /// The line, or the part of it, that could be the coffee's name; nil for
    /// a line that's only details. "Danche | Ethiopia" gives "Danche".
    static func nameCandidate(_ line: Line) -> Line? {
        // Text running up the side of a bag is the origin and process
        if line.height > line.width && line.text.count >= 3 { return nil }
        let letters = line.text.filter(\.isLetter).count
        guard letters >= 3, letters * 2 >= line.text.filter({ !$0.isWhitespace }).count else { return nil }
        let folded = fold(line.text)
        if ["www.", ".com", "@", ":"].contains(where: folded.contains) { return nil }
        let words = wordSet(folded)
        if !words.isDisjoint(with: labelWords) || words.isSubset(of: roasterWords) { return nil }

        // Tasting notes, and origin, variety and process, come as lists
        let segments = line.text.split { listSeparators.contains($0) }.map { $0.trimmingCharacters(in: .whitespaces) }
        guard segments.count < 3 else { return nil }
        let named = segments.filter { !wordSet(fold($0)).isSubset(of: detailWords) }
        guard let first = named.first else { return nil }
        if named.count == segments.count { return line }
        var part = line
        part.text = first
        return part
    }

    /// The words of folded text, without punctuation or digits.
    static func wordSet(_ folded: String) -> Set<String> {
        Set(folded.split { !$0.isLetter }.map(String.init))
    }

    /// Lowercased, without accents, so "Jijón" on the label matches "Jijon".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Whether folded `text` holds folded `phrase` as whole words, so "onyx"
    /// doesn't match "onyxa".
    static func contains(_ text: String, phrase: String) -> Bool {
        guard !phrase.isEmpty else { return false }
        var start = text.startIndex
        while let range = text.range(of: phrase, range: start..<text.endIndex) {
            let before = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
            let after = range.upperBound == text.endIndex || !text[range.upperBound].isLetter
            if before && after { return true }
            start = text.index(after: range.lowerBound)
        }
        return false
    }

    private static let listSeparators: Set<Character> = [",", "/", "|", "·", "•", ";"]

    /// Words that put a line among the label's small print.
    private static let labelWords: Set<String> = [
        "roasted", "date", "net", "wt", "weight", "oz", "masl", "altitude", "elevation", "process", "varietal",
        "variety", "notes", "tasting", "harvest", "producer", "producers", "family", "smallholders", "region", "best",
        "whole", "bean", "ground", "grams",
    ]

    /// Words in a roaster's name that aren't the name itself.
    static let roasterWords: Set<String> = [
        "coffee", "coffees", "roasters", "roaster", "roastery", "roasting", "roastworks", "co", "company", "lab", "labs",
        "works", "the",
    ]

    /// Origins, varieties, processes and roast levels: a part of a line made
    /// only of these isn't a name.
    private static let detailWords: Set<String> = [
        // Countries
        "ethiopia", "kenya", "colombia", "ecuador", "peru", "bolivia", "brazil", "burundi", "rwanda", "uganda",
        "tanzania", "congo", "drc", "yemen", "panama", "costa", "rica", "guatemala", "honduras", "nicaragua", "el",
        "salvador", "mexico", "jamaica", "hawaii", "indonesia", "sumatra", "java", "sulawesi", "timor", "papua", "new",
        "guinea", "india", "china", "yunnan", "vietnam", "thailand", "laos", "myanmar", "philippines", "taiwan",
        "malawi", "zambia", "zimbabwe", "cameroon", "dominican", "republic", "cuba", "haiti", "venezuela",
        // Regions
        "huila", "cauca", "narino", "tolima", "antioquia", "quindio", "santander", "sidama", "sidamo", "yirgacheffe",
        "guji", "jimma", "limu", "harrar", "harar", "bensa", "nyeri", "kirinyaga", "embu", "murang", "kiambu", "pichincha",
        "loja", "zamora", "cajamarca", "cusco", "puno", "boquete", "chiriqui", "antigua", "huehuetenango", "acatenango",
        "tarrazu", "minas", "gerais", "cerrado", "mogiana", "kayanza", "ngozi", "nyamasheke", "rulindo",
        // Varieties
        "landrace", "heirloom", "bourbon", "typica", "caturra", "catuai", "gesha", "geisha", "sl", "pacamara",
        "mejorado", "sidra", "castillo", "catimor", "ruiru", "batian", "jarc", "mixed", "maragogype", "pacas",
        "villa", "sarchi", "wush", "kurume", "dega", "wolisho", "chiroso", "laurina", "eugenioides", "and",
        // Processes and roasts
        "washed", "natural", "naturals", "honey", "white", "yellow", "red", "black", "anaerobic", "carbonic",
        "maceration", "fermentation", "fermented", "semi", "wet", "hulled", "pulped", "experimental", "decaf",
        "swiss", "water", "double", "thermal", "shock", "infused", "light", "ultralight", "medium", "dark", "filter",
        "espresso", "omni", "roast",
    ]
}
