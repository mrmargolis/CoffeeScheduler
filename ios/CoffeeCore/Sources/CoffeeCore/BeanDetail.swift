import Foundation

/// A brew as shown in a bag's history.
public struct BrewRecord: Hashable, Sendable {
    public var creationDate: String
    public var groundCoffeeGrams: Double
    public var rating: Double?
}

/// A freeze or thaw of a bag.
public struct FreezeEvent: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case freeze, thaw
    }

    public var kind: Kind
    public var date: String
}

/// Effective age = calendar days since roast minus days spent frozen, since
/// frozen time doesn't age the bean. Nil without a roast date; floored at 0 to
/// guard against drift between today and a planned-thaw projection.
/// Port of `effectiveAge` in `src/lib/freeze-utils.ts`.
public func effectiveAge(roastDate: String?, asOf date: String, frozenDays: Int) -> Int? {
    guard let roastDate else { return nil }
    return max(0, DateUtils.daysBetween(roastDate, date) - frozenDays)
}

/// Everything the bean detail screen derives from a bag, the projected
/// schedule and the settings. Mirrors the calculations in
/// `src/components/BeanDetail.tsx`.
public struct BeanDetail: Sendable {
    public let bean: Bean

    /// First and last scheduled day for this bag, if it appears in the schedule.
    public let start: String?
    public let finish: String?

    /// Grams used so far, never negative.
    public let consumedGrams: Double
    /// 0...1 share of the bag used.
    public let fractionConsumed: Double
    /// Roughly how many more days the bag lasts at the daily rate.
    public let daysLeft: Int?

    /// Age today and on the projected last day, frozen time excluded.
    public let currentAge: Int?
    public let calendarAge: Int?
    public let finishAge: Int?

    /// Roast → ready → today along the bag's whole life (roast to last cup, or
    /// to today when no finish is projected), as 0...1 fractions.
    public let ageTrack: AgeTrack?

    public struct AgeTrack: Hashable, Sendable {
        public let restFraction: Double
        public let todayFraction: Double
        public let end: String
    }

    /// Past this many days since roast, the last cup is flagged as old.
    public static let oldFinishAge = 60

    public init(bean: Bean, schedule: [ScheduleDay], dailyConsumptionGrams: Double, today: String) {
        self.bean = bean
        let finish = Scheduler.finishDates(schedule)[bean.id]
        self.start = Scheduler.startDates(schedule)[bean.id]
        self.finish = finish

        consumedGrams = max(0, bean.weightGrams - bean.remainingGrams)
        fractionConsumed = bean.weightGrams > 0 ? min(1, consumedGrams / bean.weightGrams) : 0
        daysLeft = dailyConsumptionGrams > 0 && bean.remainingGrams > 0
            ? Int((bean.remainingGrams / dailyConsumptionGrams).rounded())
            : nil

        currentAge = effectiveAge(roastDate: bean.roastDate, asOf: today, frozenDays: bean.frozenDays)
        calendarAge = bean.roastDate.map { DateUtils.daysBetween($0, today) }
        finishAge = finish.flatMap { effectiveAge(roastDate: bean.roastDate, asOf: $0, frozenDays: bean.frozenDays) }
        ageTrack = Self.ageTrack(bean: bean, finish: finish, today: today)
    }

    private static func ageTrack(bean: Bean, finish: String?, today: String) -> AgeTrack? {
        guard let roast = bean.roastDate, let ready = bean.readyDate else { return nil }
        let end = finish ?? today
        let total = Double(DateUtils.daysBetween(roast, end))
        guard total > 0 else { return nil }
        return AgeTrack(
            restFraction: min(1, Double(DateUtils.daysBetween(roast, ready)) / total),
            todayFraction: max(0, min(1, Double(DateUtils.daysBetween(roast, today)) / total)),
            end: end
        )
    }

    /// Country, region, variety and processing, joined for a subtitle.
    public var provenance: String {
        let origin = [bean.country, bean.region].compactMap { $0 }.joined(separator: ", ")
        return [origin.isEmpty ? nil : origin, bean.variety, bean.processing]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
