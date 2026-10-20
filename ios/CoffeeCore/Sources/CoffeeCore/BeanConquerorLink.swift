import Foundation

/// The link that opens BeanConqueror's Add bean screen filled in with a bag,
/// as a bean shared from another BeanConqueror user does. Nothing is saved
/// until it's checked and saved there.
///
/// The bag is BeanConqueror's `BeanProto` (`src/classes/bean/bean.proto` in
/// its repository), protobuf-encoded, in base64, in 400-character
/// `shareUserBean0`, `shareUserBean1`, … parameters.
public enum BeanConquerorLink {
    /// The link for the draft; nil without a coffee, which BeanConqueror
    /// needs. The roast date is midnight in `timeZone`, which BeanConqueror
    /// shows it in.
    public static func url(for draft: BagDraft, timeZone: TimeZone = .current) -> URL? {
        guard let bytes = encode(draft, timeZone: timeZone) else { return nil }
        let code = Data(bytes).base64EncodedString()
        let chunks = stride(from: 0, to: code.count, by: 400).map { start in
            let from = code.index(code.startIndex, offsetBy: start)
            return code[from..<(code.index(from, offsetBy: 400, limitedBy: code.endIndex) ?? code.endIndex)]
        }
        // "+", "/" and "=" are percent-encoded so they come through as themselves
        let alphanumerics = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let query = chunks.enumerated().map { index, chunk in
            "shareUserBean\(index)=" + (chunk.addingPercentEncoding(withAllowedCharacters: alphanumerics) ?? String(chunk))
        }
        return URL(string: "beanconqueror://ADD_USER_BEAN?" + query.joined(separator: "&"))
    }

    /// The draft as a `BeanProto`; nil without a coffee.
    static func encode(_ draft: BagDraft, timeZone: TimeZone) -> [UInt8]? {
        let name = trimmed(draft.coffee)
        guard !name.isEmpty else { return nil }
        var bean = ProtoWriter()
        bean.string(1, name)
        if let roastDate = draft.roastDate.flatMap({ instant(of: $0, in: timeZone) }) {
            bean.string(3, roastDate)
        }
        bean.string(5, trimmed(draft.roaster))
        bean.string(11, trimmed(draft.notes))
        // An integer: BeanConqueror's weight was a uint64 until September
        // 2026, and versions from before then skip a double, leaving 0 g.
        if let weight = draft.weightGrams, weight > 0 {
            bean.varint(12, UInt64(weight))
        }
        bean.string(18, trimmed(draft.url))

        var origin = ProtoWriter()
        origin.string(1, trimmed(draft.country))
        origin.string(2, trimmed(draft.region))
        origin.string(4, trimmed(draft.producer))
        origin.string(7, trimmed(draft.variety))
        origin.string(8, trimmed(draft.process))
        if !origin.bytes.isEmpty {
            bean.varint(9, 1)  // A single origin
            bean.message(21, origin.bytes)
        }
        return bean.bytes
    }

    /// Midnight at the start of an ISO day in `timeZone`, as BeanConqueror
    /// keeps dates: `2026-10-12T05:00:00.000Z` for Oct 12 in Chicago.
    static func instant(of iso: String, in timeZone: TimeZone) -> String? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, DateUtils.dayNumber(iso) != nil else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Writes the few protobuf field types a `BeanProto` needs. An empty string
/// is left out, as proto3 does.
struct ProtoWriter {
    private(set) var bytes: [UInt8] = []

    mutating func string(_ field: Int, _ text: String) {
        guard !text.isEmpty else { return }
        message(field, Array(text.utf8))
    }

    mutating func message(_ field: Int, _ body: [UInt8]) {
        key(field, wireType: 2)
        append(UInt64(body.count))
        bytes += body
    }

    mutating func varint(_ field: Int, _ value: UInt64) {
        key(field, wireType: 0)
        append(value)
    }

    private mutating func key(_ field: Int, wireType: UInt64) {
        append(UInt64(field) << 3 | wireType)
    }

    private mutating func append(_ value: UInt64) {
        var value = value
        repeat {
            let low = UInt8(value & 0x7f)
            value >>= 7
            bytes.append(value == 0 ? low : low | 0x80)
        } while value != 0
    }
}
