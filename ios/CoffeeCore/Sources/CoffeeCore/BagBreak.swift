import Foundation

/// A planned rest from a bag without freezing it: the bag is drunk until
/// `afterGrams` of it are used, then left (still ageing) until `resumeDate`,
/// when it takes its place in the queue again. A bag can have several, for
/// a few grams now, more in a fortnight and the rest later.
public struct BagBreak: Hashable, Sendable {
    /// Grams used from the full bag before the break: 150 of a 250 g bag
    /// keeps 100 g for after.
    public var afterGrams: Double
    /// The first day the bag is drunk again.
    public var resumeDate: String

    public init(afterGrams: Double, resumeDate: String) {
        self.afterGrams = afterGrams
        self.resumeDate = resumeDate
    }

    /// The break that limits the bag on `date`: of those not over by then,
    /// the one that comes first in the bag.
    static func current(_ breaks: [BagBreak], on date: String) -> BagBreak? {
        breaks.filter { $0.resumeDate > date }.min { $0.afterGrams < $1.afterGrams }
    }

    /// Grams that stay in a bag of `weightGrams` on `date`, kept for after
    /// the current break; 0 with none.
    static func floor(_ breaks: [BagBreak], weightGrams: Double, on date: String) -> Double {
        current(breaks, on: date).map { max(0, weightGrams - $0.afterGrams) } ?? 0
    }

    /// Whether a bag with `aboveGrams` left before its break is on it. The
    /// schedule takes whole doses up to a break, so less than one is none.
    static func isReached(aboveGrams: Double, doseSize: Double) -> Bool {
        aboveGrams <= Scheduler.minDoseGrams || aboveGrams < doseSize
    }
}

extension Bean {
    /// The break the bag is on, on `date`: down to the break's amount, so the
    /// schedule passes it by, until the break is over.
    public func breakOn(_ date: String) -> BagBreak? {
        guard let current = BagBreak.current(breaks, on: date) else { return nil }
        let floor = BagBreak.floor(breaks, weightGrams: weightGrams, on: date)
        return BagBreak.isReached(aboveGrams: remainingGrams - floor, doseSize: Scheduler.doseSizeGrams) ? current : nil
    }

    /// The break the bag is heading for on `date`, not yet reached.
    public func nextBreak(after date: String) -> BagBreak? {
        guard let current = BagBreak.current(breaks, on: date), breakOn(date) == nil else { return nil }
        return current
    }
}
