import Foundation

/// Port of `src/lib/scheduler.ts`. Keep the two in step: the web app and the
/// iOS app read the same database and should project the same schedule.
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
        case let (ao?, bo?): return ao == bo ? 0 : (ao < bo ? -1 : 1)
        case (.some, nil): return -1
        case (nil, .some): return 1
        case (nil, nil): break
        }

        let aInProgress = a.remainingGrams < a.weightGrams
        let bInProgress = b.remainingGrams < b.weightGrams
        if aInProgress && !bInProgress { return -1 }
        if !aInProgress && bInProgress { return 1 }

        switch (readyDate(a), readyDate(b)) {
        case let (ar?, br?): return ar == br ? 0 : (ar < br ? -1 : 1)
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
        actualBrews: [Brew],
        today: String,
        skipDays: Set<String> = [],
        consumptionOverrides: [String: DayOverride] = [:]
    ) -> [ScheduleDay] {
        var brewsByDate: [String: [Brew]] = [:]
        for brew in actualBrews {
            brewsByDate[brew.creationDate, default: []].append(brew)
        }

        // Non-frozen (or frozen with a planned thaw) beans with coffee left
        let activeBeans = sortQueue(beans.filter {
            (!$0.isFrozen || $0.plannedThawDate != nil) && $0.remainingGrams > minDoseGrams
        })

        var remaining: [String: Double] = [:]
        for bean in activeBeans { remaining[bean.id] = bean.remainingGrams }

        let beanMap = Dictionary(beans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var schedule: [ScheduleDay] = []

        for date in DateUtils.dateRange(startDate, endDate) {
            let isPast = date < today
            let isToday = date == today
            let dayBrews = brewsByDate[date] ?? []

            if skipDays.contains(date) {
                // Past day with actual brews overrides the skip
                if isPast && !dayBrews.isEmpty {
                    schedule.append(ScheduleDay(
                        date: date, consumptions: aggregate(dayBrews, beans: beanMap),
                        isGap: false, isSurplus: false, isActual: true, isSkip: false
                    ))
                } else {
                    // Skip day: no consumption, no deduction
                    schedule.append(ScheduleDay(
                        date: date, consumptions: [],
                        isGap: false, isSurplus: false, isActual: false, isSkip: true
                    ))
                }
                continue
            }

            // Past days (and today, once brewed) use actual brew data
            if isPast || isToday {
                if !dayBrews.isEmpty {
                    schedule.append(ScheduleDay(
                        date: date, consumptions: aggregate(dayBrews, beans: beanMap),
                        isGap: false, isSurplus: false, isActual: true, isSkip: false
                    ))
                    continue
                }
                if isPast {
                    schedule.append(ScheduleDay(
                        date: date, consumptions: [],
                        isGap: true, isSurplus: false, isActual: true, isSkip: false
                    ))
                    continue
                }
            }

            // Future days (or today with no brews): project consumption
            let dayOverride = consumptionOverrides[date]
            let doseSize = dayOverride?.doseSize ?? doseSizeGrams
            var gramsNeeded = dayOverride?.dailyGrams ?? dailyConsumptionGrams
            var consumptions: [Consumption] = []

            // Pre-logged brews for future days count toward the daily target
            // and deduct from the bean's remaining supply.
            let hasPreLogged = !dayBrews.isEmpty
            if hasPreLogged {
                for c in aggregate(dayBrews, beans: beanMap) {
                    consumptions.append(c)
                    remaining[c.beanID] = max(0, (remaining[c.beanID] ?? 0) - c.grams)
                    gramsNeeded -= c.grams
                }
            }

            // Count how many beans are ready on this date
            var readyCount = 0
            for bean in activeBeans {
                let rem = remaining[bean.id] ?? 0
                guard let ready = readyDate(bean), ready <= date, rem > minDoseGrams else { continue }
                // Skip bean if projected consumption has reached its freeze-after target
                if rem - freezeFloor(bean) <= minDoseGrams { continue }
                readyCount += 1
            }

            // Consume from the queue in order. Queue position is authoritative: a
            // bag that hasn't finished resting is still used rather than passed
            // over, and the consumption records how many days early it started.
            for bean in activeBeans {
                if gramsNeeded <= 0 { break }
                // Don't start a new bean just to fill a gap smaller than a minimum dose
                if !consumptions.isEmpty && gramsNeeded <= minDoseGrams { break }

                // No roast date means no ready date to be early against, and the
                // bag would otherwise block the queue forever.
                guard let ready = readyDate(bean) else { continue }
                if isInFreezer(bean, on: date) { continue }
                let daysEarly = ready > date ? DateUtils.daysBetween(date, ready) : 0

                let rem = remaining[bean.id] ?? 0
                if rem <= minDoseGrams { continue }

                // Cap available grams to respect the freeze-after target
                let floor = freezeFloor(bean)
                let effectiveRem = rem - floor
                if effectiveRem <= minDoseGrams { continue }

                var consume = min(gramsNeeded, effectiveRem)

                // If this bean can't fill the day, round down to whole doses.
                // The sub-dose remainder is wasted (or frozen).
                if consume < gramsNeeded {
                    let doses = (consume / doseSize).rounded(.down)
                    remaining[bean.id] = floor
                    if doses == 0 { continue }
                    consume = doses * doseSize
                } else {
                    remaining[bean.id] = rem - consume
                }

                consumptions.append(Consumption(
                    beanID: bean.id, beanName: bean.name, roaster: bean.roaster,
                    grams: consume, daysEarly: daysEarly > 0 ? daysEarly : nil
                ))
                gramsNeeded -= consume
            }

            // Merge pre-logged and projected consumptions for the same bean
            // (e.g. 15g pre-logged + 30g projected → 45g)
            if hasPreLogged && consumptions.count > 1 {
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
                consumptions = merged
            }

            schedule.append(ScheduleDay(
                date: date, consumptions: consumptions,
                isGap: consumptions.isEmpty && gramsNeeded > 0,
                isSurplus: readyCount > 1, isActual: false, isSkip: false
            ))
        }

        return schedule
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
