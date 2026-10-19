import Foundation

/// Asking the phone's on-device language model to read the label, and
/// checking its answer against the label.
extension BagLabel {
    /// The prompt for the on-device language model: the label's lines, top
    /// to bottom, each marked with how big it's printed.
    public static func prompt(for lines: [Line], knownRoasters: [String]) -> String {
        var prompt = """
            Below is the text read from a photo of a bag of coffee beans, top to bottom, each line marked \
            with how big it is printed. Find the roaster and the coffee's name.

            The roaster's name is usually the biggest text, a logo, often with "Coffee Roasters" or \
            "Coffee Co." under it. The coffee's name is usually a farm, a producer or a lot, and is the \
            biggest text besides the roaster's. Lines listing tasting notes (fruits, flowers, sweets), \
            countries, regions, varieties (Bourbon, Gesha, SL28) or processes (Washed, Natural, Honey) are \
            not the coffee's name.

            Reply with exactly two lines: "Roaster: " and the roaster's name, then "Coffee: " and the \
            coffee's name as printed. Leave either blank if the text doesn't say.
            """
        if !knownRoasters.isEmpty {
            prompt += "\n\nRoasters the user has bought from before: \(knownRoasters.joined(separator: ", "))."
        }
        let tallest = lines.map(\.height).max() ?? 1
        let described = lines.sorted { $0.top > $1.top }.map { "[\(size($0.height / tallest))] \($0.text)" }
        return prompt + "\n\n" + described.joined(separator: "\n")
    }

    private static func size(_ fraction: Double) -> String {
        fraction >= 0.7 ? "big" : fraction >= 0.4 ? "medium" : "small"
    }

    /// The roaster and coffee from the model's reply to `prompt`, or nil when
    /// it didn't answer in that form.
    public static func reading(fromModelAnswer answer: String) -> Reading? {
        var roaster: String?
        var coffee: String?
        for line in answer.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "")
            if let value = value(of: "roaster:", in: line) { roaster = value }
            if let value = value(of: "coffee:", in: line) { coffee = value }
        }
        guard roaster != nil || coffee != nil else { return nil }
        return Reading(roaster: roaster ?? "", coffee: coffee ?? "")
    }

    private static func value(of label: String, in line: String) -> String? {
        guard line.lowercased().hasPrefix(label) else { return nil }
        return line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
    }

    /// The model's reading where it holds up, `guess` (from `read`) where it
    /// doesn't. The model's names must be printed on the label, so it can't
    /// make one up, and its coffee can't be a line `read` knows is only
    /// details, such as "Kenya" or the tasting notes. A roaster the app
    /// knows keeps its name in the app.
    public static func checked(_ model: Reading, guess: Reading, lines: [Line], knownRoasters: [String]) -> Reading {
        let printed = Set(lines.flatMap { wordSet(fold($0.text)) })
        func isPrinted(_ text: String) -> Bool {
            let words = wordSet(fold(text))
            return !words.isEmpty && words.isSubset(of: printed)
        }
        let coffeeLine = Line(model.coffee, x: 0, y: 0, width: 1, height: 0.1)
        let namesRoaster = [model.roaster, guess.roaster].contains { !$0.isEmpty && contains(fold(model.coffee), phrase: distinctiveName($0)) }
        let coffee = isPrinted(model.coffee) && nameCandidate(coffeeLine) != nil && !namesRoaster ? model.coffee : guess.coffee

        let known = knownRoasters.first { fold($0) == fold(model.roaster) }
        let roaster: String
        if knownRoasters.contains(guess.roaster) {
            roaster = guess.roaster
        } else if let known {
            roaster = known
        } else {
            roaster = isPrinted(model.roaster) ? model.roaster : guess.roaster
        }
        return Reading(roaster: roaster, coffee: coffee)
    }
}
