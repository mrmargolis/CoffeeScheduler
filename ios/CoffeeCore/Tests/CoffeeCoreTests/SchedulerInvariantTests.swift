import Testing

@testable import CoffeeCore

/// SplitMix64: the same seed always gives the same queue.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A random queue, with brews up to today, skipped days and one-day amounts,
/// scheduled over a window around a fixed today.
private struct Scenario {
    static let today = "2026-03-01"
    static let start = "2026-02-19"
    static let end = "2026-05-30"
    static let daily: Double = 45

    var beans: [Scheduler.Bean] = []
    var brews: [Scheduler.Brew] = []
    var skipDays: Set<String> = []
    var overrides: [String: Scheduler.DayOverride] = [:]

    init(seed: UInt64) {
        var rng = SeededGenerator(state: seed)
        let window = DateUtils.dateRange(Self.start, Self.end)
        for i in 0..<Int.random(in: 1...6, using: &rng) {
            beans.append(Self.bean("b\(i)", using: &rng))
        }
        // No brews after today: those count toward a projected day's target
        for date in window where date <= Self.today && Self.chance(0.6, &rng) {
            guard let bean = beans.randomElement(using: &rng) else { continue }
            let grams = Double(Int.random(in: 1...4, using: &rng)) * 15
            brews.append(Scheduler.Brew(beanID: bean.id, creationDate: date, groundCoffeeGrams: grams))
        }
        for date in window where Self.chance(0.08, &rng) { skipDays.insert(date) }
        for date in window where Self.chance(0.08, &rng) {
            overrides[date] = Scheduler.DayOverride(
                dailyGrams: Double(Int.random(in: 15...90, using: &rng)),
                doseSize: [10, 15, 18, 20].randomElement(using: &rng) ?? 15
            )
        }
    }

    private static func chance(_ probability: Double, _ rng: inout SeededGenerator) -> Bool {
        Double.random(in: 0..<1, using: &rng) < probability
    }

    private static func bean(_ id: String, using rng: inout SeededGenerator) -> Scheduler.Bean {
        let weight: Double = [100, 200, 250, 340].randomElement(using: &rng) ?? 250
        let isFrozen = chance(0.25, &rng)
        let hasThaw = isFrozen && chance(0.6, &rng)
        return makeBean(
            id: id,
            roastDate: chance(0.1, &rng) ? nil : DateUtils.addDays(today, Int.random(in: -80...20, using: &rng)),
            weightGrams: weight,
            remainingGrams: chance(0.5, &rng) ? weight : Double(Int.random(in: 0...Int(weight), using: &rng)),
            effectiveRestDays: Int.random(in: 0...40, using: &rng),
            isFrozen: isFrozen,
            plannedThawDate: hasThaw ? DateUtils.addDays(today, Int.random(in: 1...40, using: &rng)) : nil,
            freezeAfterGrams: !isFrozen && chance(0.2, &rng) ? Double(Int.random(in: 0...Int(weight), using: &rng)) : nil,
            displayOrder: chance(0.3, &rng) ? Int.random(in: 1...6, using: &rng) : nil,
            frozenDays: isFrozen ? Int.random(in: 0...20, using: &rng) : 0
        )
    }

    var days: [ScheduleDay] {
        schedule(
            Self.start, Self.end, beans: beans, brews: brews, today: Self.today,
            daily: Self.daily, skipDays: skipDays, overrides: overrides
        )
    }

    /// The days the scheduler had to plan, rather than read from the brews.
    var projected: [ScheduleDay] { days.filter { !$0.isActual && !$0.isSkip } }

    func bean(_ id: String) -> Scheduler.Bean? { beans.first { $0.id == id } }

    func brewedGrams(on date: String) -> Double {
        brews.filter { $0.creationDate == date }.reduce(0) { $0 + $1.groundCoffeeGrams }
    }
}

/// Rules the schedule keeps whatever the queue looks like, checked over
/// random queues.
@Suite struct SchedulerInvariantTests {
    static let seeds: [UInt64] = Array(0..<300)
    static let tolerance = 1e-6

    @Test(arguments: seeds) func coversEveryDayOnce(seed: UInt64) {
        #expect(Scenario(seed: seed).days.map(\.date) == DateUtils.dateRange(Scenario.start, Scenario.end))
    }

    @Test(arguments: seeds) func skippedDaysHaveNoCoffee(seed: UInt64) {
        let scenario = Scenario(seed: seed)
        for day in scenario.days {
            if day.isSkip {
                #expect(day.consumptions.isEmpty)
                #expect(scenario.skipDays.contains(day.date))
            }
            // Brews logged on a skipped day win over the skip
            if scenario.skipDays.contains(day.date) && scenario.brewedGrams(on: day.date) == 0 {
                #expect(day.isSkip)
            }
        }
    }

    @Test(arguments: seeds) func pastDaysShowWhatWasBrewed(seed: UInt64) {
        let scenario = Scenario(seed: seed)
        for day in scenario.days where day.date < Scenario.today && !day.isSkip {
            let brewed = scenario.brewedGrams(on: day.date)
            #expect(day.isActual)
            #expect(day.isGap == (brewed == 0))
            #expect(abs(day.consumptions.reduce(0) { $0 + $1.grams } - brewed) < Self.tolerance)
        }
    }

    @Test(arguments: seeds) func projectedDayStaysWithinItsTarget(seed: UInt64) {
        let scenario = Scenario(seed: seed)
        for day in scenario.projected {
            let target = scenario.overrides[day.date]?.dailyGrams ?? Scenario.daily
            #expect(day.consumptions.reduce(0) { $0 + $1.grams } <= target + Self.tolerance)
            #expect(Set(day.consumptions.map(\.beanID)).count == day.consumptions.count)
        }
    }

    @Test(arguments: seeds) func noBagGivesMoreThanItHas(seed: UInt64) {
        let scenario = Scenario(seed: seed)
        var given: [String: Double] = [:]
        for cup in scenario.projected.flatMap(\.consumptions) { given[cup.beanID, default: 0] += cup.grams }
        for bean in scenario.beans {
            // What has to stay in the bag for the freezer
            let floor = bean.freezeAfterGrams.map { bean.weightGrams - $0 } ?? 0
            #expect(given[bean.id, default: 0] <= max(0, bean.remainingGrams - floor) + Self.tolerance)
        }
    }

    @Test(arguments: seeds) func unavailableBagsAreNeverProjected(seed: UInt64) throws {
        let scenario = Scenario(seed: seed)
        for day in scenario.projected {
            for cup in day.consumptions {
                let bean = try #require(scenario.bean(cup.beanID))
                #expect(bean.roastDate != nil)
                #expect(bean.remainingGrams > Scheduler.minDoseGrams)
                if bean.isFrozen {
                    let thaw = try #require(bean.plannedThawDate)
                    #expect(day.date >= thaw)
                }
            }
        }
    }

    @Test(arguments: seeds) func gapMeansNothingToDrink(seed: UInt64) {
        for day in Scenario(seed: seed).projected {
            #expect(day.isGap == day.consumptions.isEmpty)
        }
    }

    @Test(arguments: seeds) func earlyStartsAreCounted(seed: UInt64) throws {
        let scenario = Scenario(seed: seed)
        for day in scenario.projected {
            for cup in day.consumptions {
                let bean = try #require(scenario.bean(cup.beanID))
                let ready = try #require(Scheduler.readyDate(bean))
                #expect(cup.daysEarly == (ready > day.date ? DateUtils.daysBetween(day.date, ready) : nil))
            }
        }
    }

    @Test(arguments: seeds) func sameInputSameSchedule(seed: UInt64) {
        let scenario = Scenario(seed: seed)
        #expect(scenario.days == scenario.days)
    }
}
