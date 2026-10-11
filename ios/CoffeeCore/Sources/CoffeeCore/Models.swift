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
    /// Days frozen, with an active freeze projected to its planned thaw:
    /// what the ready date and the schedule use.
    public var frozenDays: Int
    /// Days frozen up to today, for the bag's current age.
    public var frozenDaysToDate: Int

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

/// A run of days with no coffee (travel etc.), inclusive. Row of `skip_days`.
public struct SkipRange: Hashable, Sendable, Identifiable {
    public var id: Int
    public var startDate: String
    public var endDate: String
    public var reason: String?
}

/// A different daily amount and dose size for a run of days, inclusive.
/// Row of `consumption_overrides`.
public struct ConsumptionOverride: Hashable, Sendable, Identifiable {
    public var id: Int
    public var startDate: String
    public var endDate: String
    public var dailyGrams: Double
    public var doseSizeGrams: Double

    public func covers(_ date: String) -> Bool { startDate <= date && date <= endDate }
}

public enum ConsumptionOverrideError: LocalizedError, Equatable {
    case notPositive

    public var errorDescription: String? {
        switch self {
        case .notPositive: "The day's total and the dose size must both be more than 0 g."
        }
    }
}

public struct ScheduleSettings: Hashable, Sendable {
    public var dailyConsumptionGrams: Double
    public var defaultRestDays: Int

    public init(dailyConsumptionGrams: Double, defaultRestDays: Int) {
        self.dailyConsumptionGrams = dailyConsumptionGrams
        self.defaultRestDays = defaultRestDays
    }
}

/// The settings a user edits on a bag, as the bean detail form saves them.
/// Nil clears a field.
public struct BeanSettings: Equatable, Sendable {
    /// Overrides the roaster and global default rest.
    public var restDays: Int?
    /// For bags BeanConqueror exported without one.
    public var roastDate: String?
    /// When a frozen bag comes out; auto-thaw acts on it.
    public var plannedThawDate: String?
    /// Freeze the bag once this many grams are used; auto-freeze acts on it.
    public var freezeAfterGrams: Double?

    public init(restDays: Int? = nil, roastDate: String? = nil, plannedThawDate: String? = nil, freezeAfterGrams: Double? = nil) {
        self.restDays = restDays
        self.roastDate = roastDate
        self.plannedThawDate = plannedThawDate
        self.freezeAfterGrams = freezeAfterGrams
    }

    /// The bag's current settings.
    public init(_ bean: Bean) {
        self.init(
            restDays: bean.restDays,
            roastDate: bean.roastDate,
            plannedThawDate: bean.plannedThawDate,
            freezeAfterGrams: bean.freezeAfterGrams
        )
    }

    func validate(weightGrams: Double) throws {
        if let restDays, restDays < 0 { throw BeanSettingsError.negativeRestDays }
        for date in [roastDate, plannedThawDate].compactMap({ $0 }) where DateUtils.dayNumber(date) == nil {
            throw BeanSettingsError.invalidDate(date)
        }
        if let grams = freezeAfterGrams, grams < 0 || grams > weightGrams {
            throw BeanSettingsError.freezeAfterOutOfRange(weightGrams: weightGrams)
        }
    }
}

public enum BeanSettingsError: LocalizedError, Equatable {
    case notFound
    case negativeRestDays
    case invalidDate(String)
    case freezeAfterOutOfRange(weightGrams: Double)

    public var errorDescription: String? {
        switch self {
        case .notFound: "That bag is no longer in the database."
        case .negativeRestDays: "Rest days can't be negative."
        case .invalidDate(let date): "\(date) isn't a valid date."
        case .freezeAfterOutOfRange(let weight): "Freeze-after must be between 0 and the bag's \(Int(weight)) g."
        }
    }
}
