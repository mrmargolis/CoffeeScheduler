import Foundation

/// How a cup was brewed, as far as BeanConqueror recorded it. Every field is
/// optional: an export leaves out what wasn't entered, and a zero there means
/// "not entered" rather than zero.
public struct BrewRecipe: Hashable, Sendable {
    public var grinder: String?
    /// The grinder's setting as typed, e.g. "1.6" or "4.4".
    public var grindSetting: String?
    public var temperatureC: Double?
    public var doseGrams: Double?
    public var waterGrams: Double?
    public var brewSeconds: Int?
    public var method: String?
    public var water: String?
    public var profile: String?

    public init(
        grinder: String? = nil, grindSetting: String? = nil, temperatureC: Double? = nil, doseGrams: Double? = nil,
        waterGrams: Double? = nil, brewSeconds: Int? = nil, method: String? = nil, water: String? = nil, profile: String? = nil
    ) {
        self.grinder = grinder
        self.grindSetting = grindSetting
        self.temperatureC = temperatureC
        self.doseGrams = doseGrams
        self.waterGrams = waterGrams
        self.brewSeconds = brewSeconds
        self.method = method
        self.water = water
        self.profile = profile
    }

    /// The grind setting as a number, when it reads as one.
    public var grindValue: Double? {
        grindSetting.flatMap { Double($0) }
    }

    /// Water per gram of coffee, e.g. 16 for 15 g to 240 g.
    public var ratio: Double? {
        guard let doseGrams, let waterGrams, doseGrams > 0 else { return nil }
        return waterGrams / doseGrams
    }

    /// The recipe with its text trimmed, and blank text as unknown.
    public func trimmed() -> BrewRecipe {
        func clean(_ text: String?) -> String? {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        var recipe = self
        recipe.grinder = clean(grinder)
        recipe.grindSetting = clean(grindSetting)
        recipe.method = clean(method)
        recipe.water = clean(water)
        recipe.profile = clean(profile)
        return recipe
    }

    /// True when nothing about the brew was recorded.
    public var isEmpty: Bool {
        self == BrewRecipe()
    }

    /// The recipe as short phrases for one line, leaving out what's unknown:
    /// "A4Z 1.6", "93 °C", "15 g : 240 g (1:16)", "3:28", "Hario Alpha".
    public var summaryParts: [String] {
        var parts: [String] = []
        let grind = [grinder, grindSetting].compactMap { $0 }.joined(separator: " ")
        if !grind.isEmpty { parts.append(grind) }
        if let temperatureC { parts.append("\(Self.number(temperatureC)) °C") }
        if let dose = ratioPhrase { parts.append(dose) }
        if let brewSeconds { parts.append(String(format: "%d:%02d", brewSeconds / 60, brewSeconds % 60)) }
        parts += [method, water, profile].compactMap { $0 }
        return parts
    }

    private var ratioPhrase: String? {
        switch (doseGrams, waterGrams) {
        case (let dose?, let water?):
            ratio.map { "\(Self.number(dose)) g : \(Self.number(water)) g (1:\(Self.number($0)))" }
        case (let dose?, nil): "\(Self.number(dose)) g"
        case (nil, let water?): "\(Self.number(water)) g water"
        case (nil, nil): nil
        }
    }

    /// At most one decimal, and none for a whole number.
    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}

extension BrewRecipe {
    /// A water temperature from BeanConqueror, which keeps no unit: below 101
    /// is Celsius, 101 and above is Fahrenheit. Nil for zero or less.
    public static func celsius(fromExport value: Double?) -> Double? {
        guard let value, value > 0, value.isFinite else { return nil }
        guard value >= 101 else { return value }
        return ((value - 32) * 5 / 9 * 10).rounded() / 10
    }

    /// A grind setting from BeanConqueror, which stores a number or, now and
    /// then, a string. Nil for zero or blank.
    static func grindSetting(fromExport value: JSONValue) -> String? {
        if let number = value.number {
            guard number != 0, number.isFinite else { return nil }
            return number == number.rounded() ? String(Int(number)) : String(number)
        }
        let text = value.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty || Double(text) == 0 ? nil : text
    }

    /// Reads a brew's recipe from the export, resolving the grinder, method
    /// and water from their IDs to names.
    static func fromExport(_ brew: JSONValue, names: BeanConquerorParser.Names) -> BrewRecipe {
        BrewRecipe(
            grinder: brew["mill"].string.flatMap { names.mills[$0] },
            grindSetting: grindSetting(fromExport: brew["grind_size"]),
            temperatureC: celsius(fromExport: brew["brew_temperature"].number),
            doseGrams: positive(brew["grind_weight"].number),
            waterGrams: positive(brew["brew_quantity"].number),
            brewSeconds: positive(brew["brew_time"].number).map { Int($0.rounded()) },
            method: brew["method_of_preparation"].string.flatMap { names.preparations[$0] },
            water: brew["water"].string.flatMap { names.waters[$0] },
            profile: brew["pressure_profile"].nonEmptyString
        )
    }

    private static func positive(_ value: Double?) -> Double? {
        value.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
    }
}
