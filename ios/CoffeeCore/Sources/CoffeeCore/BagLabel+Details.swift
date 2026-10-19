import Foundation

/// The rest of a bag: its roast date, weight, tasting notes and origin.
extension BagLabel {
    /// The details on a label, from its lines in reading order: what's
    /// labelled ("Process: Washed") first, then what's recognisable by its
    /// words ("Huila, Colombia", "Pink Bourbon / Washed") or form (a list of
    /// tasting notes, a date, a weight).
    public static func details(in lines: [Line], today: String) -> BagDraft {
        let texts = lines.map(\.text)
        let draft = labelled(texts, today: today)
        return draft.filling(from: recognised(texts, today: today))
    }

    /// The details on a web page, from its text: only what's labelled, since
    /// a page's menus and other coffees name countries and flavours too. The
    /// page's title, site name and address are the coffee, roaster and link.
    public static func details(ofPage text: String, title: String, site: String, url: String, today: String) -> BagDraft {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var draft = labelled(lines, today: today)
        draft.coffee = title.split(whereSeparator: \.isNewline).first.map { tidy(String($0)) } ?? ""
        draft.roaster = tidy(site)
        draft.url = url
        return draft
    }

    // MARK: Labelled

    private enum Field {
        case notes, country, region, producer, variety, process, roastDate, weight
    }

    /// Labels for each field, folded.
    private static let labels: [(Field, Set<String>)] = [
        (
            .notes,
            [
                "tasting notes", "notes", "cup notes", "cupping notes", "flavor notes", "flavour notes", "flavors",
                "flavours", "flavor", "flavour", "tastes like", "in the cup", "flavor profile", "flavour profile",
            ]
        ),
        (.country, ["origin", "country", "country of origin"]),
        (.region, ["region", "growing region", "area"]),
        (
            .producer,
            [
                "producer", "producers", "farmer", "farmers", "grower", "growers", "farm", "finca", "estate", "washing station",
                "station", "cooperative", "co-op", "coop", "mill",
            ]
        ),
        (.variety, ["variety", "varietal", "varieties", "varietals", "cultivar", "cultivars"]),
        (.process, ["process", "processing", "processing method"]),
        (.roastDate, ["roasted", "roasted on", "roast date", "date roasted", "roasted date"]),
        (.weight, ["net wt", "net wt.", "net weight", "weight", "net"]),
    ]

    private static func field(labelled label: String) -> Field? {
        let folded = fold(label).trimmingCharacters(in: .whitespaces)
        return labels.first { $0.1.contains(folded) }?.0
    }

    /// The fields given as "Label: value", "Label value" for a roast date or
    /// weight ("Roasted on Aug 5"), or a label on its own line with the value
    /// on the next.
    private static func labelled(_ lines: [String], today: String) -> BagDraft {
        var draft = BagDraft()
        for (index, line) in lines.enumerated() {
            if let colon = line.firstIndex(of: ":"), let field = field(labelled: String(line[..<colon])) {
                set(field, to: String(line[line.index(after: colon)...]), in: &draft, today: today)
            } else if let field = field(labelled: line), index + 1 < lines.count, self.field(labelled: lines[index + 1]) == nil {
                set(field, to: lines[index + 1], in: &draft, today: today)
            } else if fold(line).hasPrefix("roast") {
                set(.roastDate, to: line, in: &draft, today: today)
            } else if fold(line).hasPrefix("net") {
                set(.weight, to: line, in: &draft, today: today)
            }
        }
        return draft
    }

    /// Sets a field from a labelled value, unless it's already set.
    private static func set(_ field: Field, to value: String, in draft: inout BagDraft, today: String) {
        let value = firstSentence(value)
        guard !value.isEmpty else { return }
        switch field {
        case .notes where draft.notes.isEmpty: draft.notes = tidy(value)
        case .country where draft.country.isEmpty: draft.country = names(in: value, from: countries).first ?? tidy(value)
        case .region where draft.region.isEmpty: draft.region = tidy(value)
        case .producer where draft.producer.isEmpty: draft.producer = tidy(value)
        case .variety where draft.variety.isEmpty: draft.variety = tidy(value)
        case .process where draft.process.isEmpty: draft.process = tidy(value)
        case .roastDate where draft.roastDate == nil: draft.roastDate = date(in: value, today: today, standalone: true)
        case .weight where draft.weightGrams == nil: draft.weightGrams = weight(in: value)
        default: break
        }
    }

    /// Up to the end of the first sentence: a page's "Process: Washed. The
    /// cherries are…" is "Washed".
    private static func firstSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let end = trimmed.range(of: ". ") else { return trimmed }
        return String(trimmed[..<end.lowerBound])
    }

    // MARK: Recognised

    /// The fields found by their words or form, each from the first line that
    /// has one.
    private static func recognised(_ lines: [String], today: String) -> BagDraft {
        var draft = BagDraft()
        draft.country = lines.lazy.compactMap { names(in: $0, from: countries).first }.first ?? ""
        draft.region = lines.lazy.compactMap { names(in: $0, from: regions).first }.first ?? ""
        draft.variety = lines.lazy.map { names(in: $0, from: varieties).joined(separator: ", ") }.first { !$0.isEmpty } ?? ""
        draft.process = lines.lazy.compactMap(process(in:)).first ?? ""
        draft.notes = lines.lazy.compactMap(notes(in:)).first ?? ""
        draft.weightGrams = lines.lazy.compactMap(weight(in:)).first
        // A date on a line of its own, as a roast date is stamped; not a best before
        draft.roastDate =
            lines.lazy
            .filter { line in !["best", "exp", "use by", "bb"].contains { fold(line).contains($0) } }
            .compactMap { date(in: $0, today: today, standalone: wordSet(fold($0)).count <= 1) }
            .first
        return draft
    }

    /// The names from `list` in `text`, in the order they're printed; a name
    /// inside a longer one ("Bourbon" in "Pink Bourbon") isn't counted again.
    static func names(in text: String, from list: [Name]) -> [String] {
        let folded = fold(text)
        let found = list.flatMap { name in
            ([fold(name.name)] + name.spellings).compactMap { spelling in
                ranges(of: spelling, in: folded).map { (name: name.name, range: $0) }.first
            }
        }
        let kept = found.filter { match in
            !found.contains { $0.range != match.range && $0.range.contains(match.range.lowerBound) && $0.range.count > match.range.count }
        }
        var names: [String] = []
        for match in kept.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) where !names.contains(match.name) {
            names.append(match.name)
        }
        return names
    }

    /// Where `phrase` sits in `text` as whole words, by character offsets.
    private static func ranges(of phrase: String, in text: String) -> [Range<Int>] {
        let characters = Array(text)
        let target = Array(phrase)
        guard !target.isEmpty, characters.count >= target.count else { return [] }
        return (0...(characters.count - target.count)).compactMap { start in
            let end = start + target.count
            guard Array(characters[start..<end]) == target else { return nil }
            let before = start == 0 || !characters[start - 1].isLetter
            let after = end == characters.count || !characters[end].isLetter
            return before && after ? start..<end : nil
        }
    }

    /// A process in a line: a run of words with at least one that makes a
    /// process on its own, "White Honey" in "mixed JARC | white honey".
    static func process(in line: String) -> String? {
        let words = fold(line).split { !$0.isLetter }.map(String.init)
        var run: [String] = []
        for word in words + [""] {
            if processWords.contains(word) || processQualifiers.contains(word) {
                run.append(word)
            } else if !run.isEmpty {
                if run.contains(where: processWords.contains) { return run.joined(separator: " ").capitalized }
                run = []
            }
        }
        return nil
    }

    /// Tasting notes: a list of short items, none of them a country, region,
    /// variety or process, and no numbers.
    static func notes(in line: String) -> String? {
        guard !line.contains(where: \.isNumber), !line.contains(":") else { return nil }
        let items = line.split { listSeparators.contains($0) }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard items.count >= 2,
            // A cut-off "al" at the photo's edge isn't a note
            items.allSatisfy({ $0.split(separator: " ").count <= 3 && $0.filter(\.isLetter).count >= 3 }),
            [countries, regions, varieties].allSatisfy({ names(in: line, from: $0).isEmpty }),
            process(in: line) == nil
        else { return nil }
        return items.map(tidy).joined(separator: ", ")
    }

    /// Trimmed, and in title case when printed all in capitals.
    static func tidy(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;")))
        let letters = trimmed.filter(\.isLetter)
        return !letters.isEmpty && letters == letters.uppercased() && letters.count > 3 ? trimmed.capitalized : trimmed
    }
}
