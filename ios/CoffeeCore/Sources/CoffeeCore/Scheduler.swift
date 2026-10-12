import Foundation

/// Projects the schedule: which bags are drunk on which days.
public enum Scheduler {
    /// Minimum viable dose. Beans with less than this remaining are done.
    public static let minDoseGrams: Double = 12

    /// Typical dose size used for rounding on transition days.
    public static let doseSizeGrams: Double = 15

    /// Daily consumption assumed when the setting is missing or unreadable.
    public static let defaultDailyGrams: Double = 45

    public struct Bean: Sendable {
        public var id: String
        public var name: String
        public var roaster: String
        public var roastDate: String?
        public var weightGrams: Double
        public var remainingGrams: Double
        public var effectiveRestDays: Int
        public var isFrozen: Bool
        public var plannedThawDate: String?
        public var freezeAfterGrams: Double?
        public var displayOrder: Int?
        /// Total days spent frozen (computed from freeze_events).
        public var frozenDays: Int

        public init(
            id: String, name: String, roaster: String, roastDate: String?,
            weightGrams: Double, remainingGrams: Double, effectiveRestDays: Int,
            isFrozen: Bool = false, plannedThawDate: String? = nil,
            freezeAfterGrams: Double? = nil, displayOrder: Int? = nil, frozenDays: Int = 0
        ) {
            self.id = id
            self.name = name
            self.roaster = roaster
            self.roastDate = roastDate
            self.weightGrams = weightGrams
            self.remainingGrams = remainingGrams
            self.effectiveRestDays = effectiveRestDays
            self.isFrozen = isFrozen
            self.plannedThawDate = plannedThawDate
            self.freezeAfterGrams = freezeAfterGrams
            self.displayOrder = displayOrder
            self.frozenDays = frozenDays
        }
    }

    public struct Brew: Sendable {
        public var beanID: String
        public var creationDate: String
        public var groundCoffeeGrams: Double

        public init(beanID: String, creationDate: String, groundCoffeeGrams: Double) {
            self.beanID = beanID
            self.creationDate = creationDate
            self.groundCoffeeGrams = groundCoffeeGrams
        }
    }

    public struct DayOverride: Sendable {
        public var dailyGrams: Double
        public var doseSize: Double

        public init(dailyGrams: Double, doseSize: Double) {
            self.dailyGrams = dailyGrams
            self.doseSize = doseSize
        }
    }

    /// Ready date = roast date + effective rest days + frozen days.
    /// (Frozen time doesn't count toward resting.)
    public static func readyDate(_ bean: Bean) -> String? {
        bean.roastDate.map { DateUtils.addDays($0, bean.effectiveRestDays + bean.frozenDays) }
    }

    /// A bag still sitting in the freezer on this date can't be brewed, no matter
    /// where it sits in the queue. Frozen bags without a planned thaw date are
    /// filtered out of the queue entirely before this is consulted.
    private static func isInFreezer(_ bean: Bean, on date: String) -> Bool {
        guard bean.isFrozen, let thaw = bean.plannedThawDate else { return false }
        return date < thaw
    }

    /// Sort beans by queue priority:
    /// 1. Beans with a display order come first, sorted by it
    /// 2. Then in-progress (partially consumed) beans before untouched ones
    /// 3. Within each group, by ready date; beans with no ready date go last
    public static func sortQueue(_ beans: [Bean]) -> [Bean] {
        // Swift's sort isn't stable, so fall back to the input index to match JS.
        beans.enumerated().sorted { lhs, rhs in
            let order = compare(lhs.element, rhs.element)
            return order != 0 ? order < 0 : lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func compare(_ a: Bean, _ b: Bean) -> Int {
        switch (a.displayOrder, b.displayOrder) {
        case (let ao?, let bo?): return ao == bo ? 0 : (ao < bo ? -1 : 1)
        case (.some, nil): return -1
        case (nil, .some): return 1
        case (nil, nil): break
        }

        let aInProgress = a.remainingGrams < a.weightGrams
        let bInProgress = b.remainingGrams < b.weightGrams
        if aInProgress && !bInProgress { return -1 }
        if !aInProgress && bInProgress { return 1 }

        switch (readyDate(a), readyDate(b)) {
        case (let ar?, let br?): return ar == br ? 0 : (ar < br ? -1 : 1)
        case (.some, nil): return -1
        case (nil, .some): return 1
        case (nil, nil): return 0
        }
    }

    /// Aggregate multiple brews for the same bean on a single day into one
    /// consumption entry, in first-seen order. Does not deduct from remaining:
    /// remaining grams already account for all historical brews.
    private static func aggregate(_ brews: [Brew], beans: [String: Bean]) -> [Consumption] {
        var order: [String] = []
        var totals: [String: Double] = [:]
        for brew in brews {
            if totals[brew.beanID] == nil { order.append(brew.beanID) }
            totals[brew.beanID, default: 0] += brew.groundCoffeeGrams
        }
        return order.map { id in
            let bean = beans[id]
            return Consumption(
                beanID: id,
                beanName: bean?.name ?? "Unknown",
                roaster: bean?.roaster ?? "Unknown",
                grams: totals[id]!
            )
        }
    }

    /// Grams that must stay in the bag because it is due to be frozen.
    private static func freezeFloor(_ bean: Bean) -> Double {
        bean.freezeAfterGrams.map { bean.weightGrams - $0 } ?? 0
    }

    public static func computeSchedule(
        startDate: String,
        endDate: String,
        dailyConsumptionGrams: Double,
        beans: [Bean],
        actualBrews: [Brew] = [],
        today: String,
        skipDays: Set<String> = [],
        consumptionOverrides: [String: DayOverride] = [:]
    ) -> [ScheduleDay] {
        var brewsByDate: [String: [Brew]] = [:]
        for brew in actualBrews {
            brewsByDate[brew.creationDate, default: []].append(brew)
        }

        var projection = Projection(
            beans: beans, dailyGrams: dailyConsumptionGrams, overrides: consumptionOverrides
        )
        var schedule: [ScheduleDay] = []
        for date in DateUtils.dateRange(startDate, endDate) {
            let dayBrews = brewsByDate[date] ?? []
            let recorded = recordedDay(
                date, brews: dayBrews, today: today, isSkip: skipDays.contains(date), beans: projection.beans
            )
            schedule.append(recorded ?? projection.day(date, preLogged: dayBrews))
        }
        return schedule
    }

    /// The day as it happened or was skipped, or nil when it has to be projected.
    private static func recordedDay(
        _ date: String, brews: [Brew], today: String, isSkip: Bool, beans: [String: Bean]
    ) -> ScheduleDay? {
        let isPast = date < today
        // Past days (and today, once brewed) use actual brew data. On a past
        // day, actual brews override a skip.
        if !brews.isEmpty && (isPast || (date == today && !isSkip)) {
            return ScheduleDay(
                date: date, consumptions: aggregate(brews, beans: beans),
                isGap: false, isSurplus: false, isActual: true, isSkip: false
            )
        }
        if isSkip {
            // Skip day: no consumption, no deduction
            return ScheduleDay(
                date: date, consumptions: [],
                isGap: false, isSurplus: false, isActual: false, isSkip: true
            )
        }
        if isPast {
            return ScheduleDay(
                date: date, consumptions: [],
                isGap: true, isSurplus: false, isActual: true, isSkip: false
            )
        }
        return nil
    }
}

// MARK: - Projecting future days

extension Scheduler {
    /// The queue and what is left in each bag, as days are projected in order.
    private struct Projection {
        /// Non-frozen (or frozen with a planned thaw) beans with coffee left.
        let queue: [Bean]
        let beans: [String: Bean]
        let dailyGrams: Double
        let overrides: [String: DayOverride]
        var remaining: [String: Double] = [:]

        init(beans: [Bean], dailyGrams: Double, overrides: [String: DayOverride]) {
            queue = sortQueue(
                beans.filter {
                    (!$0.isFrozen || $0.plannedThawDate != nil) && $0.remainingGrams > minDoseGrams
                })
            self.beans = Dictionary(beans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.dailyGrams = dailyGrams
            self.overrides = overrides
            for bean in queue { remaining[bean.id] = bean.remainingGrams }
        }

        /// A future day (or today with no brews): project consumption.
        mutating func day(_ date: String, preLogged: [Brew]) -> ScheduleDay {
            let dayOverride = overrides[date]
            let doseSize = dayOverride?.doseSize ?? doseSizeGrams
            var gramsNeeded = dayOverride?.dailyGrams ?? dailyGrams

            // Pre-logged brews for future days count toward the daily target
            // and deduct from the bean's remaining supply.
            var consumptions = aggregate(preLogged, beans: beans)
            let hasPreLogged = !consumptions.isEmpty
            for c in consumptions {
                remaining[c.beanID] = max(0, (remaining[c.beanID] ?? 0) - c.grams)
                gramsNeeded -= c.grams
            }

            let readyCount = readyCount(on: date)

            // Consume from the queue in order.
            for bean in queue {
                if gramsNeeded <= 0 { break }
                // Don't start a new bean just to fill a gap smaller than a minimum dose
                if !consumptions.isEmpty && gramsNeeded <= minDoseGrams { break }
                guard let taken = take(from: bean, on: date, upTo: gramsNeeded, doseSize: doseSize)
                else { continue }
                consumptions.append(taken)
                gramsNeeded -= taken.grams
            }

            if hasPreLogged && consumptions.count > 1 {
                consumptions = mergedByBean(consumptions)
            }

            return ScheduleDay(
                date: date, consumptions: consumptions,
                isGap: consumptions.isEmpty && gramsNeeded > 0,
                isSurplus: readyCount > 1, isActual: false, isSkip: false
            )
        }

        /// How many beans are ready on this date.
        private func readyCount(on date: String) -> Int {
            queue.count { bean in
                let rem = remaining[bean.id] ?? 0
                guard let ready = readyDate(bean), ready <= date, rem > minDoseGrams else { return false }
                // Skip bean if projected consumption has reached its freeze-after target
                return rem - freezeFloor(bean) > minDoseGrams
            }
        }

        /// What `bean` gives toward the `needed` grams on `date`, or nil when
        /// it gives nothing. Queue position is authoritative: a bag that
        /// hasn't finished resting is still used rather than passed over, and
        /// the consumption records how many days early it started.
        private mutating func take(
            from bean: Bean, on date: String, upTo needed: Double, doseSize: Double
        ) -> Consumption? {
            // No roast date means no ready date to be early against, and the
            // bag would otherwise block the queue forever.
            guard let ready = readyDate(bean), !isInFreezer(bean, on: date) else { return nil }

            // Cap available grams to respect the freeze-after target
            let rem = remaining[bean.id] ?? 0
            let floor = freezeFloor(bean)
            let available = rem - floor
            guard rem > minDoseGrams, available > minDoseGrams else { return nil }

            var consume = min(needed, available)

            // If this bean can't fill the day, round down to whole doses.
            // The sub-dose remainder is wasted (or frozen).
            if consume < needed {
                let doses = (consume / doseSize).rounded(.down)
                remaining[bean.id] = floor
                if doses == 0 { return nil }
                consume = doses * doseSize
            } else {
                remaining[bean.id] = rem - consume
            }

            let daysEarly = ready > date ? DateUtils.daysBetween(date, ready) : 0
            return Consumption(
                beanID: bean.id, beanName: bean.name, roaster: bean.roaster,
                grams: consume, daysEarly: daysEarly > 0 ? daysEarly : nil
            )
        }
    }

    /// Merge pre-logged and projected consumptions for the same bean
    /// (e.g. 15g pre-logged + 30g projected → 45g).
    private static func mergedByBean(_ consumptions: [Consumption]) -> [Consumption] {
        var merged: [Consumption] = []
        for c in consumptions {
            if let i = merged.firstIndex(where: { $0.beanID == c.beanID }) {
                merged[i].grams += c.grams
                // Pre-logged entries carry no earliness; keep the projected half's
                if merged[i].daysEarly == nil { merged[i].daysEarly = c.daysEarly }
            } else {
                merged.append(c)
            }
        }
        return merged
    }

    /// Last scheduled date for each bean: its projected finish date.
    public static func finishDates(_ schedule: [ScheduleDay]) -> [String: String] {
        var result: [String: String] = [:]
        for day in schedule {
            for c in day.consumptions { result[c.beanID] = day.date }
        }
        return result
    }

    /// First scheduled date for each bean: its projected start date.
    public static func startDates(_ schedule: [ScheduleDay]) -> [String: String] {
        var result: [String: String] = [:]
        for day in schedule {
            for c in day.consumptions where result[c.beanID] == nil { result[c.beanID] = day.date }
        }
        return result
    }
}
