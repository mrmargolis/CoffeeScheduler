import Foundation

/// Dates are ISO 8601 day strings (`YYYY-MM-DD`), same as the
/// database. Arithmetic is done on whole days since 1970-01-01 so no time zone
/// or DST can shift a result; only `today()` looks at the local calendar.
public enum DateUtils {
    /// Days since 1970-01-01 for an ISO day string. Returns nil if malformed.
    public static func dayNumber(_ iso: String) -> Int? {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
            let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
            (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        return daysFromCivil(y, m, d)
    }

    /// ISO day string for a day count since 1970-01-01.
    public static func isoString(dayNumber: Int) -> String {
        let (y, m, d) = civilFromDays(dayNumber)
        return format(y, m, d)
    }

    public static func addDays(_ iso: String, _ days: Int) -> String {
        guard let n = dayNumber(iso) else { return iso }
        return isoString(dayNumber: n + days)
    }

    /// Difference in days between two ISO dates (end - start).
    public static func daysBetween(_ start: String, _ end: String) -> Int {
        guard let s = dayNumber(start), let e = dayNumber(end) else { return 0 }
        return e - s
    }

    /// ISO date strings from start to end, inclusive.
    public static func dateRange(_ start: String, _ end: String) -> [String] {
        guard let s = dayNumber(start), let e = dayNumber(end), s <= e else { return [] }
        return (s...e).map { isoString(dayNumber: $0) }
    }

    /// The calendar day `date` falls on in `timeZone`.
    public static func isoString(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return format(c.year!, c.month!, c.day!)
    }

    /// Today in the device's local time zone.
    public static func today() -> String {
        isoString(Date())
    }

    /// Add calendar months to an ISO date, clamping the day to the month's length.
    public static func addMonths(_ iso: String, _ months: Int) -> String {
        guard let n = dayNumber(iso) else { return iso }
        let (y, m, d) = civilFromDays(n)
        let total = y * 12 + (m - 1) + months
        let ny = total / 12
        let nm = total % 12 + 1
        // Length of the target month = 1st of the next month minus 1st of this one.
        let firstOfNext = nm == 12 ? daysFromCivil(ny + 1, 1, 1) : daysFromCivil(ny, nm + 1, 1)
        let monthLength = firstOfNext - daysFromCivil(ny, nm, 1)
        return isoString(dayNumber: daysFromCivil(ny, nm, min(d, monthLength)))
    }

    public static func firstOfMonth(_ iso: String) -> String {
        String(iso.prefix(8)) + "01"
    }

    private static func format(_ y: Int, _ m: Int, _ d: Int) -> String {
        func pad(_ n: Int, _ width: Int) -> String {
            let s = String(n)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(y, 4))-\(pad(m, 2))-\(pad(d, 2))"
    }

    // Howard Hinnant's days_from_civil / civil_from_days.
    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    private static func civilFromDays(_ days: Int) -> (Int, Int, Int) {
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
}
