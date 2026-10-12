import Foundation
import ZIPFoundation

/// Reads a BeanConqueror export ZIP.
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

    /// Parse an export ZIP. Brew dates use `timeZone` (the device's by default).
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
        guard let main = json(mainEntry, in: archive) else {
            return ParseResult(errors: ["Failed to parse Beanconqueror.json"])
        }

        var result = ParseResult()
        let roastDates = parseBeans(main["BEANS"].array ?? [], into: &result)

        // Collect all brews: main file + split files
        var rawBrews = main["BREWS"].array ?? []
        let splitFiles = archive.filter {
            $0.path.range(of: #"^Beanconqueror_Brews_\d+\.json$"#, options: .regularExpression) != nil
        }
        for entry in splitFiles {
            // Without every brew file the bags would look fuller than they
            // are, so an unreadable one fails the whole export.
            guard let split = json(entry, in: archive) else {
                return ParseResult(errors: ["Failed to parse \(entry.path)"])
            }
            rawBrews += split.array ?? []
        }

        parseBrews(rawBrews, roastDates: roastDates, timeZone: timeZone, into: &result)
        return result
    }

    /// Adds the beans and the freeze events of those still frozen to `result`.
    /// Returns each bean's roast date, for the brews' bean age.
    private static func parseBeans(_ beans: [JSONValue], into result: inout ParseResult) -> [String: String] {
        var roastDates: [String: String] = [:]
        for (i, b) in beans.enumerated() {
            guard let id = b["config"]["uuid"].string, !id.isEmpty else {
                result.errors.append("Bean index \(i): missing config.uuid, skipping")
                continue
            }

            let bean = rawBean(b, id: id)
            result.beans.append(bean)
            if let roastDate = bean.roastDate { roastDates[id] = roastDate }

            // Record a freeze event for currently frozen beans
            if bean.isFrozen, let frozenDate = parseIsoDate(b["frozenDate"].string) {
                result.freezeEvents.append(FreezeInfo(beanID: id, frozenDate: frozenDate))
            }
        }
        return roastDates
    }

    private static func rawBean(_ b: JSONValue, id: String) -> RawBean {
        let info = b["bean_information"].array?.first ?? .null
        let frozenID = b["frozenId"].string ?? ""
        let unfrozenDate = b["unfrozenDate"].string ?? ""

        return RawBean(
            id: id,
            name: b["name"].string ?? "",
            roaster: b["roaster"].string ?? "",
            roastDate: parseIsoDate(b["roastingDate"].string),
            weightGrams: b["weight"].number ?? 0,
            cost: b["cost"].number.flatMap { $0 == 0 ? nil : $0 },
            flavourProfile: b["aromatics"].nonEmptyString,
            country: info["country"].nonEmptyString,
            region: info["region"].nonEmptyString,
            variety: info["variety"].nonEmptyString,
            processing: info["processing"].nonEmptyString,
            archived: b["finished"].isTruthy,
            isFrozen: !frozenID.isEmpty && unfrozenDate.isEmpty
        )
    }

    /// Adds the brews to `result`, deduplicating by config.uuid.
    private static func parseBrews(
        _ brews: [JSONValue], roastDates: [String: String], timeZone: TimeZone, into result: inout ParseResult
    ) {
        var seenBrewIDs = Set<String>()
        for (i, br) in brews.enumerated() {
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

            result.brews.append(
                RawBrew(
                    beanID: beanID,
                    groundCoffeeGrams: br["grind_weight"].number ?? 0,
                    creationDate: creationDate,
                    beanAgeDays: roastDates[beanID].map { DateUtils.daysBetween($0, creationDate) },
                    rating: br["rating"].number.flatMap { $0 == 0 ? nil : $0 }
                ))
        }
    }

    /// An entry's contents as JSON, or nil when it can't be read or parsed.
    private static func json(_ entry: Entry, in archive: Archive) -> JSONValue? {
        guard let data = try? read(entry, from: archive) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
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

/// Loosely typed JSON, so the parser can check a field's type as it reads it
/// without a Codable model for BeanConqueror's whole export format.
enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
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
