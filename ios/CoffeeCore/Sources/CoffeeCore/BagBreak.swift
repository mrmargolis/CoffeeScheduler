import Foundation

/// A break in a bag, without freezing it: the bag is drunk until
/// `afterGrams` of it are used, and the rest waits at its own place in the
/// queue, so the bags above that place are drunk first. A bag can have
/// several, each splitting off another part of it.
public struct BagBreak: Hashable, Sendable {
    public var id: Int
    /// Grams used from the full bag before the break: 150 of a 250 g bag
    /// keeps 100 g for after.
    public var afterGrams: Double
    /// Where the rest of the bag sits in the queue, numbered with the bags'
    /// `displayOrder`; nil puts it after the bag that follows the part before.
    public var displayOrder: Int?

    public init(id: Int, afterGrams: Double, displayOrder: Int? = nil) {
        self.id = id
        self.afterGrams = afterGrams
        self.displayOrder = displayOrder
    }

    /// Whether a part with `aboveGrams` left before its break is drunk. The
    /// schedule takes whole doses up to a break, so less than one is none.
    static func isReached(aboveGrams: Double, doseSize: Double) -> Bool {
        aboveGrams <= Scheduler.minDoseGrams || aboveGrams < doseSize
    }
}

/// A bag as the queue splits it at its breaks.
public protocol QueueBag: QueueOrdered {
    var id: String { get }
    /// Earliest in the bag first.
    var breaks: [BagBreak] { get }
    var freezeAfterGrams: Double? { get }
}

extension Bean: QueueBag {}
extension Scheduler.Bean: QueueBag {}

/// A stretch of a bag in the queue: the whole bag, or, with breaks, the bag
/// up to its first break and the rest after each one.
public struct QueuePart<B: QueueBag>: Identifiable {
    public let bean: B
    /// 0 for the bag up to its first break; k for the rest after its k-th.
    public let index: Int
    /// The break the part comes back from; nil for the first part.
    public let after: BagBreak?
    /// The break that ends it; nil for the last part.
    public let until: BagBreak?

    /// The bag's ID for its first part, `key(breakID:)` for the rest.
    public var id: String { after.map { Self.key(breakID: $0.id) } ?? bean.id }

    /// The rest of the bag after a break, rather than the bag itself.
    public var isRest: Bool { after != nil }

    /// Grams of the full bag used where the part starts and ends.
    public var startGrams: Double { after?.afterGrams ?? 0 }
    public var endGrams: Double { until?.afterGrams ?? bean.weightGrams }

    /// Grams that stay in the bag once the part is drunk: the parts after
    /// it, or what's to be frozen.
    public var floorGrams: Double { max(bean.weightGrams - endGrams, freezeFloor) }

    /// Ends at a break, rather than at the bag's end or its freeze-after.
    var keepsRest: Bool { until != nil && bean.weightGrams - endGrams > freezeFloor }

    private var freezeFloor: Double { bean.freezeAfterGrams.map { bean.weightGrams - $0 } ?? 0 }

    /// Grams the part has left in it, before what stays for later.
    public var leftGrams: Double { max(0, bean.remainingGrams - floorGrams) }

    /// Drunk down to its break, with less than a dose left before it. The
    /// last part is never done here: it ends with the bag.
    func isDone(remaining: Double, doseSize: Double) -> Bool {
        keepsRest && BagBreak.isReached(aboveGrams: remaining - floorGrams, doseSize: doseSize)
    }

    /// Back from its break: more than the part before it used.
    public var isStarted: Bool { !isRest || bean.weightGrams - bean.remainingGrams > startGrams }

    public static func key(breakID: Int) -> String { "break:\(breakID)" }

    /// The break whose rest `key` names; nil for a bag's ID.
    public static func breakID(in key: String) -> Int? {
        key.hasPrefix("break:") ? Int(key.dropFirst("break:".count)) : nil
    }
}

extension QueuePart: QueueOrdered {
    public var displayOrder: Int? { after.map(\.displayOrder) ?? bean.displayOrder }
    public var weightGrams: Double { bean.weightGrams }
    public var remainingGrams: Double { bean.remainingGrams }
    public var readyDate: String? { bean.readyDate }
}

extension Scheduler {
    /// The bag's parts, first to last.
    public static func parts<B: QueueBag>(of bean: B) -> [QueuePart<B>] {
        let breaks = bean.breaks.sorted { $0.afterGrams < $1.afterGrams }
        return (0...breaks.count).map { k in
            QueuePart(
                bean: bean, index: k, after: k > 0 ? breaks[k - 1] : nil, until: k < breaks.count ? breaks[k] : nil)
        }
    }

    /// The part the bag is in: the first not drunk down to its break.
    public static func currentPart<B: QueueBag>(of bean: B, doseSize: Double = doseSizeGrams) -> QueuePart<B> {
        let parts = parts(of: bean)
        return parts.first { !$0.isDone(remaining: bean.remainingGrams, doseSize: doseSize) } ?? parts[parts.count - 1]
    }

    /// The queue in the order the schedule drinks it, a row per part: each
    /// bag from the part it's in, and the rest after each break at the
    /// break's own place, or, without one, after the next row.
    public static func queue<B: QueueBag>(_ beans: [B], doseSize: Double = doseSizeGrams) -> [QueuePart<B>] {
        let bags = beans.map { parts(of: $0) }
        var order = sortQueue(bags.flatMap { parts in parts.filter { !$0.isRest || $0.displayOrder != nil } })
        for parts in bags {
            for part in parts.dropFirst() { place(part, afterPart: parts[part.index - 1].id, in: &order) }
        }
        let current = Dictionary(beans.map { ($0.id, currentPart(of: $0, doseSize: doseSize).index) }) { first, _ in first }
        return order.filter { $0.index >= current[$0.bean.id] ?? 0 }
    }

    /// Keeps a part below the one before it: one without a place, or put
    /// above it, goes after the row that follows that part.
    private static func place<B>(_ part: QueuePart<B>, afterPart previous: String, in order: inout [QueuePart<B>]) {
        let index = order.firstIndex { $0.id == part.id }
        let before = order.firstIndex { $0.id == previous } ?? -1
        if let index, index > before { return }
        if let index { order.remove(at: index) }
        let after = order.firstIndex { $0.id == previous } ?? -1
        order.insert(part, at: min(after + 2, order.count))
    }

    /// The queue's IDs with each rest kept below the part before it, for a
    /// drag that left one above: it goes just below instead.
    public static func keepingPartsInOrder<B>(_ ids: [String], parts: [QueuePart<B>]) -> [String] {
        var ids = ids
        for part in parts where part.isRest {
            guard let earlier = parts.first(where: { $0.bean.id == part.bean.id && $0.index == part.index - 1 }),
                let index = ids.firstIndex(of: part.id), let before = ids.firstIndex(of: earlier.id), index < before
            else { continue }
            ids.remove(at: index)
            ids.insert(part.id, at: before)
        }
        return ids
    }
}

extension Scheduler {
    /// Each part of a bag's run through the schedule, by `QueuePart.id`: for
    /// a rest, the day it's taken up again, and its last. Brews already made
    /// count towards the bag's first part.
    public static func partRuns(_ schedule: [ScheduleDay]) -> [String: BagRun] {
        var runs: [String: BagRun] = [:]
        for day in schedule {
            for c in day.consumptions {
                let part = c.partID ?? c.beanID
                if runs[part] != nil {
                    runs[part]!.end = day.date
                    runs[part]!.grams += c.grams
                } else {
                    runs[part] = BagRun(
                        beanID: c.beanID, name: c.beanName, roaster: c.roaster, start: day.date, end: day.date, grams: c.grams)
                }
            }
        }
        return runs
    }
}
