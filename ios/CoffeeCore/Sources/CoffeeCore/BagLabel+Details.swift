import Foundation

/// The rest of a bag: its roast date, weight, tasting notes and origin.
extension BagLabel {
    /// The details on a label, from its lines in reading order: what's
    /// labelled ("Process: Washed"), which is stated, and else what's
    /// recognisable by its words ("Huila, Colombia", "Pink Bourbon / Washed")
    /// or form (a list of tasting notes, a date, a weight), which is guessed.
    /// A date like 10/08 that could be either is read as `monthFirst` says.
    public static func details(in lines: [Line], today: String, monthFirst: Bool = regionIsMonthFirst) -> BagDraft {
        let texts = lines.map(\.text)
        return labelled(texts, today: today, monthFirst: monthFirst)
            .merging(recognised(texts, today: today, monthFirst: monthFirst))
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
                "coffee flavor profile", "coffee flavour profile", "tasting profile", "cup profile", "i taste", "we taste",
            ]
        ),
        (.country, ["origin", "country", "country of origin", "from"]),
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
    static func labelled(_ lines: [String], today: String, monthFirst: Bool) -> BagDraft {
        var draft = BagDraft()
        for (index, line) in lines.enumerated() {
            // The value on the next line, under a label of its own ("I taste:")
            let next = lines.indices.contains(index + 1) ? lines[index + 1] : ""
            let nextIsValue = !next.isEmpty && field(labelled: next) == nil && !next.hasSuffix(":")
            if let colon = line.firstIndex(of: ":"), let field = field(labelled: String(line[..<colon])) {
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                set(field, to: value.isEmpty && nextIsValue ? next : value, in: &draft, today: today, monthFirst: monthFirst)
            } else if let field = field(labelled: line), nextIsValue {
                set(field, to: next, in: &draft, today: today, monthFirst: monthFirst)
            } else if fold(line).hasPrefix("roast") {
                set(.roastDate, to: line, in: &draft, today: today, monthFirst: monthFirst)
            } else if fold(line).hasPrefix("net") {
                set(.weight, to: line, in: &draft, today: today, monthFirst: monthFirst)
            }
        }
        return draft
    }

    /// Sets a field from a labelled value, as stated, unless it's already
    /// set. A value that's a sentence ("Pacamara, a cross between Pacas and
    /// Maragogipe…") gives only the names in it, as guesses, and so does a
    /// date whose day and month could be either way round.
    private static func set(_ field: Field, to value: String, in draft: inout BagDraft, today: String, monthFirst: Bool) {
        let value = cleaned(value)
        guard !value.isEmpty else { return }
        let isSentence = value.split(separator: " ").count > 8
        var found = BagDraft()
        switch field {
        case .notes: found = notes(labelled: value)
        case .country, .region: found = origin(value, labelledAsRegion: field == .region, isSentence: isSentence)
        case .producer: found.producer = isSentence ? "" : tidy(value, name: true)
        // A sentence names a variety's parents too ("a cross between Pacas and…"), and a
        // process's steps ("before being pulped"): only its first variety, and no process
        case .variety: found.variety = isSentence ? names(in: value, from: varieties).first ?? "" : tidy(value)
        case .process: found.process = isSentence ? "" : tidy(value)
        case .roastDate: found = roastDate(value, today: today, monthFirst: monthFirst)
        case .weight: found.weightGrams = weight(in: value)
        }
        if isSentence {
            for field in BagField.allCases where found.has(field) { found.certainty[field] = .guessed }
        }
        fillEmpty(&draft, from: found)
    }

    /// A labelled roast date; a guess when its day and month could be
    /// either way round ("10.08.26").
    private static func roastDate(_ value: String, today: String, monthFirst: Bool) -> BagDraft {
        var found = BagDraft()
        let dated = dated(value, today: today, standalone: true, monthFirst: monthFirst)
        found.roastDate = dated?.iso
        if dated?.isGuess == true { found.certainty[.roastDate] = .guessed }
        return found
    }

    /// Labelled notes; a description ("We taste juicy and tart black
    /// currants, …") rather than a list is only a guess.
    private static func notes(labelled value: String) -> BagDraft {
        var found = BagDraft()
        found.notes = tidy(value)
        if value.split(whereSeparator: listSeparators.contains).contains(where: { $0.split(separator: " ").count > 4 }) {
            found.certainty[.notes] = .guessed
        }
        return found
    }

    /// The country and region in an origin or region: "Nyeri, Kenya",
    /// "Kenya - Nyeri County", "Suke Quto, Odo Shakisso, Guji, Ethiopia". A
    /// labelled region is the whole value but its country; in an origin, the
    /// region is one the app recognises, else what's beside the country.
    private static func origin(_ value: String, labelledAsRegion: Bool, isSentence: Bool) -> BagDraft {
        var found = BagDraft()
        let country = names(in: value, from: countries).first
        found.country = country ?? (labelledAsRegion || isSentence ? "" : tidy(value))
        let rest = value.components(separatedBy: CharacterSet(charactersIn: ",–—")).flatMap { $0.components(separatedBy: " - ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && names(in: $0, from: countries).isEmpty }
            .joined(separator: ", ")
        let known = names(in: value, from: regions).first
        if isSentence {
            found.region = known ?? ""
        } else if labelledAsRegion {
            found.region = tidy(rest)
        } else {
            found.region = known ?? (country == nil ? "" : tidy(rest))
        }
        return found
    }

    /// A labelled value up to the end of its first sentence, without asides
    /// in brackets, and only its lead when that's followed by a colon:
    /// "Washed: Fermented in open concrete tanks…" is "Washed".
    private static func cleaned(_ value: String) -> String {
        let value = firstSentence(withoutAsides(value))
        guard let colon = value.firstIndex(of: ":"), value[..<colon].split(separator: " ").count <= 4 else { return value }
        return String(value[..<colon])
    }

    /// Without asides in brackets: "Landrace(most varietals in Ethiopia are…)".
    private static func withoutAsides(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s*\([^)]*\)?"#, with: "", options: .regularExpression)
    }

    /// Fills the draft's empty fields from `found`, as stated unless `found`
    /// says otherwise: the first label for a field wins.
    static func fillEmpty(_ draft: inout BagDraft, from found: BagDraft) {
        var found = found
        for field in BagField.allCases where found.has(field) {
            if draft.has(field) {
                found.clear(field)
            } else if found.certainty[field] == nil {
                found.certainty[field] = .stated
            }
        }
        draft = draft.merging(found)
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
    private static func recognised(_ lines: [String], today: String, monthFirst: Bool) -> BagDraft {
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
            .compactMap { date(in: $0, today: today, standalone: wordSet(fold($0)).count <= 1, monthFirst: monthFirst) }
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
        return items.map { tidy($0) }.joined(separator: ", ")
    }

    /// Trimmed, and in title case when printed all in capitals, as many
    /// labels are: "LUME COFFEE ROASTERS" is "Lume Coffee Roasters". A
    /// `name` (a coffee, roaster or producer) printed all in lowercase, as
    /// some roasters style them, is put in title case too. Codes are in
    /// capitals: a grade ("Gititu AB"), "USA", "SL28".
    public static func tidy(_ text: String, name: Bool = false) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;")))
        let letters = trimmed.filter(\.isLetter)
        let shouted = letters == letters.uppercased()
        guard letters.count >= 2, shouted || (name && letters == letters.lowercased()) else { return trimmed }
        return trimmed.split(separator: " ", omittingEmptySubsequences: false).map { word in
            let bare = String(word.filter(\.isLetter)).lowercased()
            if codes.contains(bare) { return word.uppercased() }
            return word.contains(where: \.isNumber) ? String(word) : word.capitalized
        }
        .joined(separator: " ")
    }

    /// Words a label prints in capitals that stay that way.
    private static var codes: Set<String> {
        ["aa", "ab", "aaa", "pb", "ea", "sl", "jarc", "usa", "uk", "nyc", "drc", "png", "ii", "iii", "iv"]
    }
}
