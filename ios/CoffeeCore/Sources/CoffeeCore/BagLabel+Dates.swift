import Foundation

/// Reading a roast date and a bag's weight from a line of a label.
extension BagLabel {
    /// The date in `text`, `YYYY-MM-DD`, or nil. A date without a year is
    /// the latest one that isn't after `today`; one after `today` is a best
    /// before, not a roast date. A bare "4.4" is a date only when
    /// `standalone`, so a weight like "4.4 oz" isn't read as one.
    static func date(in text: String, today: String, standalone: Bool, monthFirst: Bool) -> String? {
        dated(text, today: today, standalone: standalone, monthFirst: monthFirst)?.iso
    }

    /// A date, `YYYY-MM-DD`, and whether its day and month were a guess.
    typealias Dated = (iso: String, isGuess: Bool)

    /// The date in `text`, and whether its order was a guess. Numbers like
    /// 10/08 are read the one way that's a day by `today`, whatever their
    /// separator; when both are, in the order the phone's region writes
    /// dates (`monthFirst`), as a guess.
    static func dated(_ text: String, today: String, standalone: Bool, monthFirst: Bool) -> Dated? {
        let folded = fold(text)
        if let match = groups(#"(?<![0-9])(\d{4})[-./](\d{1,2})[-./](\d{1,2})(?![0-9])"#, in: folded) {
            return day(year: Int(match[1] ?? ""), month: Int(match[2] ?? ""), day: Int(match[3] ?? ""), today: today)
                .map { ($0, false) }
        }
        let numeric = #"(?<![0-9./-])(\d{1,2})([./-])(\d{1,2})(?:\2(\d{4}|\d{2}))?(?![0-9]|\.[0-9]|\s*(?:oz|g|kg|lb))"#
        if let match = groups(numeric, in: folded) {
            guard match[4] != nil || standalone else { return nil }
            return numericDate(
                Int(match[1] ?? "") ?? 0, Int(match[3] ?? "") ?? 0, year: match[4].flatMap { Int($0) }, today: today,
                monthFirst: monthFirst)
        }
        return namedDate(folded, today: today).map { ($0, false) }
    }

    /// A date of numbers, the month first or second.
    private static func numericDate(_ first: Int, _ second: Int, year: Int?, today: String, monthFirst: Bool) -> Dated? {
        let monthFirstDay = day(year: year, month: first, day: second, today: today)
        let dayFirstDay = day(year: year, month: second, day: first, today: today)
        switch (monthFirstDay, dayFirstDay) {
        case (let month?, let day?): return (monthFirst ? month : day, month != day)
        case (let month?, nil): return (month, false)
        case (nil, let day?): return (day, false)
        case (nil, nil): return nil
        }
    }

    /// A date with its month's name: "Aug 5", "3rd October 2026".
    private static func namedDate(_ folded: String, today: String) -> String? {
        let months = "(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?"
        let year = #"(?:,?\s*('?\d{4}|'?\d{2})(?![0-9]))?"#
        if let match = groups(months + #"\s*(\d{1,2})(?:st|nd|rd|th)?(?![0-9])"# + year, in: folded) {
            return day(year: Self.year(match[3]), month: month(match[1]), day: Int(match[2] ?? ""), today: today)
        }
        if let match = groups(#"(?<![0-9])(\d{1,2})(?:st|nd|rd|th)?\s*(?:of\s+)?"# + months + year, in: folded) {
            return day(year: Self.year(match[3]), month: month(match[2]), day: Int(match[1] ?? ""), today: today)
        }
        return nil
    }

    /// Whether the phone's region writes dates month first, as the US does.
    public static var regionIsMonthFirst: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: .current) ?? "M/d"
        guard let month = format.firstIndex(of: "M"), let day = format.firstIndex(of: "d") else { return true }
        return month < day
    }

    /// The first match's capture groups, nil for a group that didn't take
    /// part; the whole match is group 0.
    static func groups(_ pattern: String, in text: String) -> [String?]? {
        allGroups(pattern, in: text).first
    }

    static func allGroups(_ pattern: String, in text: String) -> [[String?]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { match in
            (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : nsText.substring(with: range)
            }
        }
    }

    private static func month(_ name: String?) -> Int? {
        ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"].firstIndex { $0 == name }.map { $0 + 1 }
    }

    private static func year(_ text: String?) -> Int? {
        text.flatMap { Int($0.replacingOccurrences(of: "'", with: "")) }
    }

    /// The ISO day, if it's a real one on or before `today`.
    private static func day(year: Int?, month: Int?, day: Int?, today: String) -> String? {
        guard let month, let day, let todayYear = Int(today.prefix(4)) else { return nil }
        let candidates = year.map { [$0 < 100 ? 2000 + $0 : $0] } ?? [todayYear, todayYear - 1]
        return candidates.lazy
            .map { String(format: "%04d-%02d-%02d", $0, month, day) }
            .first { iso in
                // A real day: February 30th comes back as March
                guard let number = DateUtils.dayNumber(iso), DateUtils.isoString(dayNumber: number) == iso else { return false }
                return iso <= today
            }
    }

    /// The weight in `text` in grams, or nil: "250g", "12 oz", "1 kg".
    /// Grams win over ounces printed beside them, being exact.
    static func weight(in text: String) -> Int? {
        let pattern = #"(?<![0-9.,])(\d+(?:[.,]\d+)?)\s*(kg|g|grams?|oz|ounces?|lbs?|pounds?)(?![a-z])"#
        let amounts = allGroups(pattern, in: fold(text))
            .compactMap { match -> (grams: Double, metric: Bool)? in
                guard let number = match[1], let unit = match[2], let amount = Double(number.replacingOccurrences(of: ",", with: "."))
                else { return nil }
                switch unit.prefix(1) {
                case "k": return (amount * 1000, true)
                case "g": return (amount, true)
                case "o": return (amount * 28.3495, false)
                default: return (amount * 453.592, false)
                }
            }
            .filter { (50...5000).contains($0.grams) }
        guard let amount = amounts.first(where: \.metric) ?? amounts.first else { return nil }
        return Int(amount.grams.rounded())
    }
}
