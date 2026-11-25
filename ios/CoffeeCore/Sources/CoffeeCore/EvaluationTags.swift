import Foundation

/// How an evaluation's tags and notes are kept in the database: JSON for
/// the tags, trimmed text for the notes.
enum EvaluationTags {
    static func characterJSON(_ character: [CharacterTag: TagSource]) -> String? {
        guard !character.isEmpty else { return nil }
        let object = Dictionary(uniqueKeysWithValues: character.map { ($0.key.rawValue, $0.value.rawValue) })
        return json(object)
    }

    static func character(fromJSON text: String?) -> [CharacterTag: TagSource] {
        guard let data = text?.data(using: .utf8),
            let object = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        var character: [CharacterTag: TagSource] = [:]
        for (tag, source) in object {
            if let tag = CharacterTag(rawValue: tag) { character[tag] = TagSource(rawValue: source) ?? .user }
        }
        return character
    }

    /// Trimmed, blanks dropped, and each flavour once whatever its case.
    static func flavoursJSON(_ flavours: [String]) -> String? {
        var seen = Set<String>()
        let kept = flavours.compactMap(clean).filter { seen.insert($0.lowercased()).inserted }
        return kept.isEmpty ? nil : json(kept)
    }

    static func flavours(fromJSON text: String?) -> [String] {
        guard let data = text?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Trimmed, and nil when blank.
    static func clean(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func json(_ value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
