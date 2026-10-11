import Foundation

/// A bag of coffee with the values the app derives from brews and settings.
/// Mirrors `BeanWithComputed` in the web app (`src/lib/types.ts`).
public struct Bean: Identifiable, Hashable, Sendable {
    public var id: String // UUID from BeanConqueror
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
    // User-managed fields
    public var restDays: Int?
    public var isFrozen: Bool
    public var plannedThawDate: String?
    public var freezeAfterGrams: Double?
    public var notes: String?
    public var displayOrder: Int?
    // Computed
    public var effectiveRestDays: Int
    public var totalBrewedGrams: Double
    public var frozenDays: Int

    public var remainingGrams: Double { weightGrams - totalBrewedGrams }

    public var readyDate: String? {
        roastDate.map { DateUtils.addDays($0, effectiveRestDays + frozenDays) }
    }
}

public struct Consumption: Hashable, Sendable {
    public var beanID: String
    public var beanName: String
    public var roaster: String
    public var grams: Double
    /// > 0 when this bag was started before its ready date.
    public var daysEarly: Int?

    public init(beanID: String, beanName: String, roaster: String, grams: Double, daysEarly: Int? = nil) {
        self.beanID = beanID
        self.beanName = beanName
        self.roaster = roaster
        self.grams = grams
        self.daysEarly = daysEarly
    }
}

public struct ScheduleDay: Hashable, Sendable, Identifiable {
    public var date: String
    public var consumptions: [Consumption]
    /// No coffee available.
    public var isGap: Bool
    /// Multiple bags ready.
    public var isSurplus: Bool
    /// Uses real brew data (past day).
    public var isActual: Bool
    /// User marked as skip day (traveling, etc.).
    public var isSkip: Bool

    public var id: String { date }
}

public struct ScheduleSettings: Hashable, Sendable {
    public var dailyConsumptionGrams: Double
    public var defaultRestDays: Int

    public init(dailyConsumptionGrams: Double, defaultRestDays: Int) {
        self.dailyConsumptionGrams = dailyConsumptionGrams
        self.defaultRestDays = defaultRestDays
    }
}
