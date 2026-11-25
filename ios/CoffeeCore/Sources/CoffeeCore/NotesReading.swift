import Foundation

/// What a reader found in a cup's notes: character tags and flavours to
/// propose. Never ratings.
public struct NotesReading: Hashable, Sendable {
    public var character: Set<CharacterTag>
    /// Short and lowercase, as tasted: "peach", "pink flowers".
    public var flavours: [String]

    public init(character: Set<CharacterTag> = [], flavours: [String] = []) {
        self.character = character
        self.flavours = flavours
    }
}

/// Reads the notes typed on the evaluation sheet. The app's reader uses the
/// on-device language model; tests use a fake.
public protocol NotesReader: Sendable {
    /// Nil when it can't read them (no model, or it failed).
    func read(_ notes: String) async -> NotesReading?
}

/// The prompt for the language model, and how its answer is read.
public enum NotesPrompt {
    /// Most flavours taken from one answer.
    static let maxFlavours = 6

    public static func prompt(for notes: String) -> String {
        """
        These are notes about one cup of pour-over coffee. Find what the cup tasted like.

        The notes mix three things. Only the third counts:
        1. The recipe: pour schedules like "50/150/240" or "45/75/195H/250", grams, pour rates like "6g/s", times like "1:30", \
        temperatures, grind settings, filters, drippers, kettles, swirls and jiggles.
        2. Plans and advice: what to try next ("try coarser", "go finer", "drop temp", "next time", "maybe 1:15"), \
        and what someone else said.
        3. How this cup tasted.

        Character: tag only problems this cup had, from this list.
        - sharp: acidity that was sour, harsh, sharp or biting. More acidity, or bright, juicy or tart acidity, is not sharp.
        - muddy: murky, muddled or blurry flavours, or a silty or dirty cup.
        - bitter: bitter, ashy, burnt or harsh roast.
        - heavy: body that was too heavy, thick or clogging.
        Leave a tag out when the notes say it was absent or gone ("no bitterness", "less sour now").

        Flavours: specific things tasted in this cup, like fruits, flowers, sweets, spices or teas: "peach", "pink flowers", \
        "butterscotch". One to three words each, lowercase. Leave out general words (sweet, bright, clean, watery, thin, \
        floral body, good), anything only planned or hoped for, and anything the notes say was missing ("not much watermelon", \
        "no honey").

        Answer with exactly two lines and nothing else:
        character: <tags from the list, separated by commas, or none>
        flavours: <flavours separated by commas, or none>

        Notes:
        \(notes)
        """
    }

    /// The model's answer read leniently: lines in any order and case,
    /// unknown character tags dropped, flavours trimmed, lowercased, kept
    /// short and each kept once. Character words aren't flavours.
    public static func reading(fromAnswer answer: String) -> NotesReading {
        var reading = NotesReading()
        for line in answer.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: decoration).lowercased()
            let items = items(String(parts[1]))
            if key.hasPrefix("character") {
                reading.character = Set(items.compactMap(CharacterTag.init(rawValue:)))
            } else if key.hasPrefix("flavo") {
                reading.flavours = flavours(items)
            }
        }
        return reading
    }

    /// Spaces, quotes, brackets and Markdown around a key or an item.
    private static let decoration = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.<>[]*-#`"))

    private static func items(_ list: String) -> [String] {
        list.split(separator: ",")
            .map { $0.trimmingCharacters(in: decoration).lowercased() }
            .filter { !$0.isEmpty && $0 != "none" }
    }

    private static func flavours(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return
            items
            .filter { $0.split(separator: " ").count <= 3 && CharacterTag(rawValue: $0) == nil }
            .filter { seen.insert($0).inserted }
            .prefix(maxFlavours)
            .map { $0 }
    }
}

extension CupEvaluation {
    /// Take a reading of the notes as proposals. Character tags the drinker
    /// set stay as they are; the model's own tags from an earlier reading
    /// are replaced by this one's; a tag in `rejected` (one the drinker
    /// removed) isn't proposed again. Returns the flavours to offer: ones
    /// not already on the cup or rejected, which become the drinker's only
    /// when added.
    public mutating func takeProposals(
        _ reading: NotesReading, rejected: Set<CharacterTag> = [], rejectedFlavours: Set<String> = []
    ) -> [String] {
        character = character.filter { $0.value == .user }
        for tag in reading.character where character[tag] == nil && !rejected.contains(tag) {
            character[tag] = .model
        }
        let have = Set(flavours.map { $0.lowercased() })
        return reading.flavours.filter { !have.contains($0.lowercased()) && !rejectedFlavours.contains($0.lowercased()) }
    }

    /// Make a proposed character tag the drinker's own.
    public mutating func accept(_ tag: CharacterTag) {
        if character[tag] != nil { character[tag] = .user }
    }
}
