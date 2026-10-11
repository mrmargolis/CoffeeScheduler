import Foundation
import ZIPFoundation

/// Port of `src/lib/bc-json-parser.ts`: reads a BeanConqueror export ZIP.
public enum BeanConquerorParser {
    public struct RawBean: Equatable, Sendable {
        public var id: String
        public var name: String
        public var roaster: String
        public var roastDate: String?
        public var weightGrams: Double
        public var cost: Double?
        public var flavourProfile: String?
        public var country: String?
        public var region: String?
        public var variety: String?
        public var processing: String?
        public var archived: Bool
        public var isFrozen: Bool
    }

    public struct RawBrew: Equatable, Sendable {
        public var beanID: String
        public var groundCoffeeGrams: Double
        public var creationDate: String
        public var beanAgeDays: Int?
        public var rating: Double?
    }

    public struct FreezeInfo: Equatable, Sendable {
        public var beanID: String
        public var frozenDate: String
    }

    public struct ParseResult: Sendable {
        public var beans: [RawBean] = []
        public var brews: [RawBrew] = []
        public var freezeEvents: [FreezeInfo] = []
        public var errors: [String] = []
    }

    /// Parse an export ZIP. Brew dates use `timeZone` (the device's by default),
    /// matching the web app, which uses the server's local time zone.
    public static func parse(zipData: Data, timeZone: TimeZone = .current) -> ParseResult {
        let archive: Archive
        do {
            archive = try Archive(data: zipData, accessMode: .read)
        } catch {
            return ParseResult(errors: ["Not a valid ZIP file"])
        }

        guard let mainEntry = archive["Beanconqueror.json"] else {
            return ParseResult(errors: ["No Beanconqueror.json found in ZIP"])
        }
        guard let mainData = try? read(mainEntry, from: archive),
              let main = try? JSONDecoder().decode(JSONValue.self, from: mainData)
        else {
            return ParseResult(errors: ["Failed to parse Beanconqueror.json"])
        }

        var result = ParseResult()
        var roastDates: [String: String] = [:]

        for (i, b) in (main["BEANS"].array ?? []).enumerated() {
            guard let id = b["config"]["uuid"].string, !id.isEmpty else {
                result.errors.append("Bean index \(i): missing config.uuid, skipping")
                continue
            }

            let roastDate = parseIsoDate(b["roastingDate"].string)
            if let roastDate { roastDates[id] = roastDate }

            let info = b["bean_information"].array?.first ?? .null
            let frozenID = b["frozenId"].string ?? ""
            let unfrozenDate = b["unfrozenDate"].string ?? ""
            let isFrozen = !frozenID.isEmpty && unfrozenDate.isEmpty

            result.beans.append(RawBean(
                id: id,
                name: b["name"].string ?? "",
                roaster: b["roaster"].string ?? "",
                roastDate: roastDate,
                weightGrams: b["weight"].number ?? 0,
                cost: b["cost"].number.flatMap { $0 == 0 ? nil : $0 },
                flavourProfile: b["aromatics"].nonEmptyString,
                country: info["country"].nonEmptyString,
                region: info["region"].nonEmptyString,
                variety: info["variety"].nonEmptyString,
                processing: info["processing"].nonEmptyString,
                archived: b["finished"].isTruthy,
                isFrozen: isFrozen
            ))

            // Record a freeze event for currently frozen beans
            if isFrozen, let frozenDate = parseIsoDate(b["frozenDate"].string) {
                result.freezeEvents.append(FreezeInfo(beanID: id, frozenDate: frozenDate))
            }
        }

        // Collect all brews: main file + split files
        var rawBrews = main["BREWS"].array ?? []
        let splitFiles = archive.filter {
            $0.path.range(of: #"^Beanconqueror_Brews_\d+\.json$"#, options: .regularExpression) != nil
        }
        for entry in splitFiles {
            if let data = try? read(entry, from: archive),
               let split = try? JSONDecoder().decode(JSONValue.self, from: data) {
                rawBrews += split.array ?? []
            } else {
                result.errors.append("Failed to parse \(entry.path)")
            }
        }

        // Parse brews, deduplicating by config.uuid
        var seenBrewIDs = Set<String>()
        for (i, br) in rawBrews.enumerated() {
            if let brewID = br["config"]["uuid"].string, !brewID.isEmpty {
                if seenBrewIDs.contains(brewID) { continue }
                seenBrewIDs.insert(brewID)
            }

            guard let beanID = br["bean"].string, !beanID.isEmpty else {
                result.errors.append("Brew index \(i): missing bean reference, skipping")
                continue
            }

            guard let ts = br["config"]["unix_timestamp"].number, ts != 0, ts.isFinite else {
                result.errors.append("Brew index \(i): invalid creation date, skipping")
                continue
            }
            let creationDate = DateUtils.isoString(Date(timeIntervalSince1970: ts), timeZone: timeZone)

            result.brews.append(RawBrew(
                beanID: beanID,
                groundCoffeeGrams: br["grind_weight"].number ?? 0,
                creationDate: creationDate,
                beanAgeDays: roastDates[beanID].map { DateUtils.daysBetween($0, creationDate) },
                rating: br["rating"].number.flatMap { $0 == 0 ? nil : $0 }
            ))
        }

        return result
    }

    private static func read(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }

    /// Extract YYYY-MM-DD from an ISO 8601 timestamp like "2024-06-15T21:26:00.000Z".
    static func parseIsoDate(_ s: String?) -> String? {
        guard let s, s.count >= 10 else { return nil }
        let day = String(s.prefix(10))
        guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              DateUtils.dayNumber(day) != nil
        else { return nil }
        return day
    }
}

/// Loosely typed JSON, so the parser can treat fields the way the TypeScript
/// version does (`typeof x === "number"`, `x || null`) without a Codable model
/// for BeanConqueror's whole export format.
enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    subscript(key: String) -> JSONValue {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// The string, or nil when it is missing or empty.
    var nonEmptyString: String? {
        string.flatMap { $0.isEmpty ? nil : $0 }
    }

    var number: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// JavaScript truthiness, for `!!value`.
    var isTruthy: Bool {
        switch self {
        case .null: false
        case .bool(let b): b
        case .number(let n): n != 0 && !n.isNaN
        case .string(let s): !s.isEmpty
        case .array, .object: true
        }
    }
}
