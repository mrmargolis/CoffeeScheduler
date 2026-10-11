import Testing
@testable import CoffeeCore

// Ported from src/__tests__/lib/colors.test.ts.
@Suite struct RoasterColorTests {
    @Test func stableForTheSameRoaster() {
        #expect(RoasterColor.forRoaster("Square Mile") == RoasterColor.forRoaster("Square Mile"))
    }

    @Test func pairsARailWithItsTintAndText() {
        let c = RoasterColor.forRoaster("Square Mile")
        for hex in [c.border, c.bg, c.text] {
            #expect(hex.count == 7 && hex.hasPrefix("#"))
        }
    }

    @Test func matchesTheWebHash() {
        // JavaScript: Math.abs of the 32-bit (h << 5) - h + charCode hash
        #expect(RoasterColor.hash("") == 0)
        #expect(RoasterColor.hash("a") == 97)
        #expect(RoasterColor.hash("ab") == 3105)
        #expect(RoasterColor.hash("Square Mile") % 10 == RoasterColor.hash("La Cabra") % 10)
    }

    @Test func separatesRoastersThatHashToTheSameSlot() {
        // These two collide under the plain hash
        #expect(RoasterColor.forRoaster("Square Mile").border == RoasterColor.forRoaster("La Cabra").border)
        let assigned = RoasterColor.assign(["Square Mile", "La Cabra"])
        #expect(assigned["Square Mile"]?.border != assigned["La Cabra"]?.border)
    }

    @Test func keepsTheHashedColourWhenFree() {
        #expect(RoasterColor.assign(["Square Mile"])["Square Mile"] == RoasterColor.forRoaster("Square Mile"))
    }

    @Test func tenRoastersGetTenColours() {
        let roasters = [
            "Square Mile", "La Cabra", "Coffee Collective", "Has Bean", "Friedhats",
            "Tim Wendelboe", "Origin", "Kiss the Hippo", "Assembly", "Workshop",
        ]
        #expect(Set(RoasterColor.assign(roasters).values.map(\.border)).count == roasters.count)
    }

    @Test func deterministicForTheSameOrder() {
        let roasters = ["Square Mile", "La Cabra", "Friedhats"]
        #expect(RoasterColor.assign(roasters) == RoasterColor.assign(roasters))
    }

    @Test func everyRoasterGetsAColourPastThePaletteSize() {
        let roasters = (0..<14).map { "Roaster \($0)" }
        let assigned = RoasterColor.assign(roasters)
        #expect(assigned.count == 14)
    }

    @Test func aRepeatedRoasterIsAssignedOnce() {
        #expect(RoasterColor.assign(["Square Mile", "Square Mile"]).count == 1)
    }
}

private func makeDay(
    _ date: String, _ uses: [(id: String, grams: Double, early: Int?)] = [],
    gap: Bool = false, skip: Bool = false, actual: Bool = false
) -> ScheduleDay {
    ScheduleDay(
        date: date,
        consumptions: uses.map {
            Consumption(beanID: $0.id, beanName: $0.id == "b1" ? "Ethiopia" : "Colombia", roaster: "SM", grams: $0.grams, daysEarly: $0.early)
        },
        isGap: gap, isSurplus: false, isActual: actual, isSkip: skip
    )
}

// Ported from src/__tests__/lib/calendar-utils.test.ts.
@Suite struct CalendarSpanTests {
    func beanEvents(_ events: [CalendarEvent], _ id: String = "b1") -> [CalendarEvent] {
        events.filter { $0.beanID == id }
    }

    @Test func mergesConsecutiveSingleBagDays() {
        let events = CalendarSpans.events(schedule: [
            makeDay("2026-03-01", [("b1", 45, nil)]),
            makeDay("2026-03-02", [("b1", 45, nil)]),
            makeDay("2026-03-03", [("b1", 45, nil)]),
        ])
        let spans = beanEvents(events)
        #expect(spans.count == 1)
        #expect(spans.first?.start == "2026-03-01")
        #expect(spans.first?.end == "2026-03-04") // exclusive
        #expect(spans.first?.title == "Ethiopia")
        #expect(spans.first?.meta == "3 d · 135 g")
    }

    @Test func breaksSpansAtSkipDaysAndShowsTheReason() {
        let events = CalendarSpans.events(
            schedule: [
                makeDay("2026-03-01", [("b1", 45, nil)]),
                makeDay("2026-03-02", skip: true),
                makeDay("2026-03-03", [("b1", 45, nil)]),
            ],
            skipRanges: [SkipRange(id: 1, startDate: "2026-03-02", endDate: "2026-03-02", reason: "Travel")]
        )
        #expect(beanEvents(events).count == 2)
        let skips = events.filter { $0.kind == .skip }
        #expect(skips.map(\.title) == ["Travel"])
    }

    @Test func skipWithoutAReasonSaysSkip() {
        let events = CalendarSpans.events(
            schedule: [makeDay("2026-03-02", skip: true)],
            skipRanges: [SkipRange(id: 1, startDate: "2026-03-02", endDate: "2026-03-02", reason: nil)]
        )
        #expect(events.map(\.title) == ["Skip"])
    }

    @Test func projectedGapsAreMarked() {
        let events = CalendarSpans.events(schedule: [makeDay("2026-03-01", gap: true)])
        #expect(events.filter { $0.kind == .gap }.map(\.title) == ["No coffee"])
    }

    @Test func pastDaysWithoutBrewsAreNotMarkedAsGaps() {
        let events = CalendarSpans.events(schedule: [makeDay("2026-03-01", gap: true, actual: true)])
        #expect(events.isEmpty)
    }

    @Test func multiBagDaysGetOneEventPerBag() {
        let events = CalendarSpans.events(schedule: [
            makeDay("2026-03-01", [("b1", 45, nil)]),
            makeDay("2026-03-02", [("b1", 30, nil), ("b2", 15, nil)]),
        ])
        #expect(events.map(\.start) == ["2026-03-01", "2026-03-02", "2026-03-02"])
        #expect(events.map(\.meta) == ["1 d · 45 g", "30 g", "15 g"])
    }

    @Test func splitsWhereBrewedDaysMeetProjectedOnes() {
        let events = CalendarSpans.events(schedule: [
            makeDay("2026-03-01", [("b1", 45, nil)], actual: true),
            makeDay("2026-03-02", [("b1", 45, nil)], actual: true),
            makeDay("2026-03-03", [("b1", 45, nil)]),
        ])
        let spans = beanEvents(events)
        #expect(spans.count == 2)
        #expect(spans[0].isActual)
        #expect(spans[0].end == "2026-03-03")
        #expect(spans[0].meta == "2 d · 90 g")
        #expect(!spans[1].isActual)
        #expect(spans[1].start == "2026-03-03")
    }

    @Test func flagsASpanStartedBeforeTheBagRested() {
        let spans = beanEvents(CalendarSpans.events(schedule: [
            makeDay("2026-03-01", [("b1", 45, 4)]),
            makeDay("2026-03-02", [("b1", 45, nil)]),
        ]))
        #expect(spans.count == 1)
        #expect(spans.first?.daysEarly == 4)
    }

    @Test func overrideDaysAreMarked() {
        let events = CalendarSpans.events(
            schedule: [makeDay("2026-03-01", [("b1", 60, nil)])],
            overrides: [ConsumptionOverride(id: 1, startDate: "2026-03-01", endDate: "2026-03-01", dailyGrams: 60, doseSizeGrams: 20)]
        )
        #expect(events.filter { $0.kind == .override }.map(\.title) == ["60 g/day"])
    }
}

// Ported from collectBagRuns in src/__tests__/lib/schedule-html.test.ts.
@Suite struct BagRunTests {
    @Test func collapsesEachBagIntoOneRun() {
        let runs = Scheduler.bagRuns([
            makeDay("2026-06-21", [("b1", 45, nil)]),
            makeDay("2026-06-22", [("b1", 45, nil)]),
            makeDay("2026-06-23", [("b1", 30, nil)]),
        ])
        #expect(runs.count == 1)
        #expect(runs.first?.beanID == "b1")
        #expect(runs.first?.start == "2026-06-21")
        #expect(runs.first?.end == "2026-06-23")
        #expect(runs.first?.grams == 120)
    }

    @Test func keepsBagsInTheOrderTheyAreFirstDrunk() {
        let runs = Scheduler.bagRuns([
            makeDay("2026-06-21", [("b2", 45, nil)]),
            makeDay("2026-06-22", [("b1", 45, nil)]),
        ])
        #expect(runs.map(\.beanID) == ["b2", "b1"])
    }
}
