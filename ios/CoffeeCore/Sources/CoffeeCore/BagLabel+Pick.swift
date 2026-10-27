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
        return BagField.allCases.filter(found.has)
    }

    /// What picking a line for `field` puts there: what the line says the
    /// field is ("Hambela Estate" from "Producer: Hambela Estate"), or else
    /// the whole line, tidied, for a text field. Nil for a roast date or
    /// weight the line doesn't hold.
    public static func value(in text: String, for field: BagField, today: String, monthFirst: Bool = regionIsMonthFirst) -> String? {
        let found = details(in: [Line(text, x: 0, y: 0, width: 1, height: 0.05)], today: today, monthFirst: monthFirst)
        if found.has(field), let value = found.value(field) { return value }
        return field.text == nil ? nil : tidy(text)
    }
}

extension BagLabel.Line {
    /// Where the line sits on its photo, from the top left, in points of a
    /// photo `width` by `height`. Vision measures from the bottom left.
    public func frame(width: Double, height: Double) -> CGRect {
        CGRect(x: x * width, y: (1 - y - self.height) * height, width: self.width * width, height: self.height * height)
    }
}
