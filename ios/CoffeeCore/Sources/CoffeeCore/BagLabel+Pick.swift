import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Picking a line of a label or page by hand, for a field.
extension BagLabel {
    /// The fields a line looks like it holds, in the form's order:
    /// "Roasted 14.10.26" the roast date, "ETHIOPIA · GUJI" the country and
    /// region.
    public static func likelyFields(in text: String, today: String, monthFirst: Bool = regionIsMonthFirst) -> [BagField] {
        let found = details(in: [Line(text, x: 0, y: 0, width: 1, height: 0.05)], today: today, monthFirst: monthFirst)
        let dated = pickedDate(in: text, today: today, monthFirst: monthFirst) != nil
        return BagField.allCases.filter { found.has($0) || ($0 == .roastDate && dated) }
    }

    /// What picking a line for `field` puts there: what the line says the
    /// field is ("Hambela Estate" from "Producer: Hambela Estate"), or else
    /// the whole line, tidied, for a text field. Nil for a roast date or
    /// weight the line doesn't hold.
    public static func value(in text: String, for field: BagField, today: String, monthFirst: Bool = regionIsMonthFirst) -> String? {
        if field == .roastDate { return pickedDate(in: text, today: today, monthFirst: monthFirst) }
        let found = details(in: [Line(text, x: 0, y: 0, width: 1, height: 0.05)], today: today, monthFirst: monthFirst)
        if found.has(field), let value = found.value(field) { return value }
        return field.text == nil ? nil : tidy(text)
    }

    /// The date in a line picked for the roast date. Picking it says it's a
    /// date, so it needn't be on a line of its own ("9/18 HSCR" off a box's
    /// sticker), and spaces around its separators ("9 / 18") and an O or I
    /// read in place of a digit ("O9/18/26") don't stop it.
    static func pickedDate(in text: String, today: String, monthFirst: Bool) -> String? {
        let digits =
            text
            .replacingOccurrences(of: #"(?<=\d)\s*([./-])\s*(?=\d)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[Oo](?=\d|[./-]\d)|(?<=\d|\d[./-])[Oo]"#, with: "0", options: .regularExpression)
            .replacingOccurrences(of: #"[Il|](?=\d|[./-]\d)|(?<=\d|\d[./-])[Il|]"#, with: "1", options: .regularExpression)
        return dated(digits, today: today, standalone: true, monthFirst: monthFirst)?.iso
    }
}

extension BagLabel.Line {
    /// Where the line sits on its photo, from the top left, in points of a
    /// photo `width` by `height`. Vision measures from the bottom left.
    public func frame(width: Double, height: Double) -> CGRect {
        CGRect(x: x * width, y: (1 - y - self.height) * height, width: self.width * width, height: self.height * height)
    }
}
