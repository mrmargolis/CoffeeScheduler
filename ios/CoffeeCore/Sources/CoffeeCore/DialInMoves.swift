import Foundation

/// A move sized against the current recipe: the values to show, or none
/// when only the direction is known.
struct PlannedMove {
    var from: String?
    var to: String?
    var toValue: Double?
}

extension DialInMove {
    /// Water temperatures a suggestion stays within, in °C.
    static let temperatureRange = 85.0...100.0
    /// Ratios a suggestion stays within: 1:10 to 1:20.
    static let ratioRange = 10.0...20.0

    /// Sizes the move for `recipe`, or nil when it's blocked: ruled out by
    /// the context, at the end of its range, or (except grind, which can
    /// always be given as a direction) not known in the recipe.
    func plan(for recipe: CupRecipe, in context: DialInContext) -> PlannedMove? {
        guard !context.blocked.contains(variable) else { return nil }
        switch variable {
        case .grind: return planGrind(recipe.brew, grinder: context.grinder)
        case .temperature: return planTemperature(recipe.brew, step: context.temperatureStep)
        case .ratio: return planRatio(recipe.brew)
        case .agitation: return planAgitation(recipe.agitation)
        }
    }

    /// Exact when the setting, the grinder's step and its direction are
    /// known and the setting is in its usual range; else a direction.
    private func planGrind(_ brew: BrewRecipe, grinder: GrinderSetting?) -> PlannedMove {
        guard let value = brew.grindValue, let grinder, grinder.name == brew.grinder, let step = grinder.effectiveStep,
            !grinder.history.isUnusual(value)
        else { return PlannedMove() }
        let sign = Double(numberDirection(grinder: grinder))
        let places = max(GrinderHistory.decimalPlaces(step), GrinderHistory.decimalPlaces(value))
        let next = GrinderHistory.round(value + sign * step, places: places)
        guard next > 0 else { return PlannedMove() }
        let name = brew.grinder.map { "\($0) " } ?? ""
        return PlannedMove(from: "\(name)\(Self.grindNumber(value))", to: Self.grindNumber(next), toValue: next)
    }

    private func planTemperature(_ brew: BrewRecipe, step: Double) -> PlannedMove? {
        guard let current = brew.temperatureC else { return nil }
        let next = current + (direction == .up ? step : -step)
        guard Self.temperatureRange.contains(next) else { return nil }
        return PlannedMove(from: "\(Self.number(current)) °C", to: "\(Self.number(next)) °C", toValue: next)
    }

    /// A shorter ratio (up) is one point less water per gram, at the same dose.
    private func planRatio(_ brew: BrewRecipe) -> PlannedMove? {
        guard let dose = brew.doseGrams, let ratio = brew.ratio else { return nil }
        let next = (ratio + (direction == .up ? -1 : 1)).rounded()
        guard Self.ratioRange.contains(next) else { return nil }
        let water = (dose * next).rounded()
        return PlannedMove(
            from: "1:\(Self.number(ratio)) (\(Self.number(brew.waterGrams ?? 0)) g)", to: "1:\(Self.number(next)) (\(Self.number(water)) g)",
            toValue: water)
    }

    private func planAgitation(_ current: Agitation?) -> PlannedMove? {
        guard let current else { return nil }
        let levels = Agitation.allCases
        guard let index = levels.firstIndex(of: current) else { return nil }
        let nextIndex = index + (direction == .up ? 1 : -1)
        guard levels.indices.contains(nextIndex) else { return nil }
        return PlannedMove(from: current.rawValue, to: levels[nextIndex].rawValue, toValue: Double(nextIndex))
    }

    /// Which way the variable's number goes: grind finer is a lower number
    /// where higher is coarser (the default when the grinder isn't known);
    /// a shorter ratio is less water per gram.
    func numberDirection(grinder: GrinderSetting?) -> Int {
        switch variable {
        case .grind: (direction == .down) == (grinder?.higherIsCoarser ?? true) ? 1 : -1
        case .ratio: direction == .up ? -1 : 1
        case .temperature, .agitation: direction == .up ? 1 : -1
        }
    }

    static func number(_ value: Double) -> String { BrewRecipe.number(value) }

    /// Up to two decimals, none trailing: 1.75, 1.7, 4.
    static func grindNumber(_ value: Double) -> String {
        var text = String(format: "%.2f", GrinderHistory.round(value, places: 2))
        while text.contains("."), text.hasSuffix("0") || text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
