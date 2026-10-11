import Testing
@testable import CoffeeCore

func makeDetailBean(
    roastDate: String? = "2026-01-01",
    weightGrams: Double = 250,
    totalBrewedGrams: Double = 100,
    effectiveRestDays: Int = 30,
    frozenDays: Int = 0,
    frozenDaysToDate: Int? = nil,
    country: String? = nil,
    region: String? = nil,
    variety: String? = nil,
    processing: String? = nil
) -> Bean {
    Bean(
        id: "b1", name: "Test Bean", roaster: "Roaster", roastDate: roastDate,
        weightGrams: weightGrams, cost: nil, flavourProfile: nil,
        country: country, region: region, variety: variety, processing: processing,
        archived: false, restDays: nil, isFrozen: false, plannedThawDate: nil,
        freezeAfterGrams: nil, notes: nil, displayOrder: nil,
        effectiveRestDays: effectiveRestDays, totalBrewedGrams: totalBrewedGrams,
        frozenDays: frozenDays, frozenDaysToDate: frozenDaysToDate ?? frozenDays
    )
}

func day(_ date: String, _ beanIDs: String...) -> ScheduleDay {
    ScheduleDay(
        date: date,
        consumptions: beanIDs.map { Consumption(beanID: $0, beanName: $0, roaster: "R", grams: 45) },
        isGap: beanIDs.isEmpty, isSurplus: false, isActual: false, isSkip: false
    )
}

@Suite struct BeanDetailTests {
    let schedule = [
        day("2026-02-08", "other"),
        day("2026-02-09", "other", "b1"),
        day("2026-02-10", "b1"),
        day("2026-02-11", "b1"),
        day("2026-02-12", "other"),
    ]

    @Test func scheduleWindow() {
        let detail = BeanDetail(bean: makeDetailBean(), schedule: schedule, dailyConsumptionGrams: 45, today: "2026-02-01")
        #expect(detail.start == "2026-02-09")
        #expect(detail.finish == "2026-02-11")
    }

    @Test func notInSchedule() {
        let detail = BeanDetail(bean: makeDetailBean(), schedule: [], dailyConsumptionGrams: 45, today: "2026-02-01")
        #expect(detail.start == nil)
        #expect(detail.finish == nil)
        #expect(detail.finishAge == nil)
    }

    @Test func consumption() {
        let detail = BeanDetail(bean: makeDetailBean(), schedule: [], dailyConsumptionGrams: 45, today: "2026-02-01")
        #expect(detail.consumedGrams == 100)
        #expect(detail.fractionConsumed == 0.4)
        #expect(detail.daysLeft == 3) // 150 g / 45 g = 3.33
    }

    @Test func noDaysLeftWhenEmptyOrNoRate() {
        let empty = BeanDetail(bean: makeDetailBean(totalBrewedGrams: 250), schedule: [], dailyConsumptionGrams: 45, today: "2026-02-01")
        #expect(empty.daysLeft == nil)
        let noRate = BeanDetail(bean: makeDetailBean(), schedule: [], dailyConsumptionGrams: 0, today: "2026-02-01")
        #expect(noRate.daysLeft == nil)
    }

    @Test func overBrewedBagClampsToFull() {
        let detail = BeanDetail(bean: makeDetailBean(totalBrewedGrams: 300), schedule: [], dailyConsumptionGrams: 45, today: "2026-02-01")
        #expect(detail.fractionConsumed == 1)
    }

    @Test func agesExcludeFrozenTime() {
        let detail = BeanDetail(bean: makeDetailBean(frozenDays: 10), schedule: schedule, dailyConsumptionGrams: 45, today: "2026-02-01")
        #expect(detail.calendarAge == 31)
        #expect(detail.currentAge == 21)
        #expect(detail.startAge == 29) // Feb 9 is 39 calendar days after roast
        #expect(detail.finishAge == 31) // Feb 11 is 41 calendar days after roast
    }

    @Test func startAgeOfABagAlreadyStartedIgnoresFreezerTimeToCome() {
        // Started Feb 9, frozen 10 days so far and 25 by the planned thaw
        let bean = makeDetailBean(frozenDays: 25, frozenDaysToDate: 10)
        let detail = BeanDetail(bean: bean, schedule: schedule, dailyConsumptionGrams: 45, today: "2026-02-10")
        #expect(detail.startAge == 29)
        #expect(detail.finishAge == 16)
    }

    @Test func ageRangesByBag() {
        let ranges = Scheduler.ageRanges(schedule, beans: [makeDetailBean()], today: "2026-02-01")
        #expect(ranges == ["b1": AgeRange(start: 39, finish: 41)]) // "other" isn't a known bag
        #expect(Scheduler.ageRanges(schedule, beans: [makeDetailBean(roastDate: nil)], today: "2026-02-01").isEmpty)
    }

    @Test func currentAgeCountsFreezerTimeOnlyToToday() {
        // Frozen 10 days so far, thawing after 25: today's age uses the 10
        let bean = makeDetailBean(frozenDays: 25, frozenDaysToDate: 10)
        let detail = BeanDetail(bean: bean, schedule: schedule, dailyConsumptionGrams: 45, today: "2026-02-01")
        #expect(detail.currentAge == 21)
        #expect(detail.finishAge == 16) // Feb 11: 41 calendar days - 25 frozen
    }

    @Test func ageTrackToProjectedFinish() throws {
        // Roast Jan 1, ready Jan 31, today Feb 1, last cup Feb 11: 41 days in all
        let detail = BeanDetail(bean: makeDetailBean(), schedule: schedule, dailyConsumptionGrams: 45, today: "2026-02-01")
        let track = try #require(detail.ageTrack)
        #expect(track.end == "2026-02-11")
        #expect(track.restFraction == 30.0 / 41)
        #expect(track.todayFraction == 31.0 / 41)
    }

    @Test func ageTrackEndsTodayWithoutFinish() throws {
        let detail = BeanDetail(bean: makeDetailBean(), schedule: [], dailyConsumptionGrams: 45, today: "2026-01-21")
        let track = try #require(detail.ageTrack)
        #expect(track.end == "2026-01-21")
        #expect(track.restFraction == 1) // still resting: rest runs past today
        #expect(track.todayFraction == 1)
    }

    @Test func noAgeTrackWithoutRoastDateOrOnRoastDay() {
        #expect(BeanDetail(bean: makeDetailBean(roastDate: nil), schedule: [], dailyConsumptionGrams: 45, today: "2026-02-01").ageTrack == nil)
        #expect(BeanDetail(bean: makeDetailBean(), schedule: [], dailyConsumptionGrams: 45, today: "2026-01-01").ageTrack == nil)
    }

    @Test func provenance() {
        let full = makeDetailBean(country: "Ethiopia", region: "Guji", variety: "Heirloom", processing: "Natural")
        #expect(BeanDetail(bean: full, schedule: [], dailyConsumptionGrams: 45, today: "2026-02-01").provenance
            == "Ethiopia, Guji · Heirloom · Natural")
        let partial = makeDetailBean(region: "Huila", processing: "Washed")
        #expect(BeanDetail(bean: partial, schedule: [], dailyConsumptionGrams: 45, today: "2026-02-01").provenance
            == "Huila · Washed")
        #expect(BeanDetail(bean: makeDetailBean(), schedule: [], dailyConsumptionGrams: 45, today: "2026-02-01").provenance == "")
    }
}

@Suite struct BeanHistoryQueryTests {
    @Test func beanByID() throws {
        let store = try CoffeeStore.inMemory()
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()]), timeZone: utc))
        #expect(try store.bean(id: "uuid-1")?.name == "Test Bean")
        #expect(try store.bean(id: "missing") == nil)
    }

    @Test func recentBrewsNewestFirstAndLimited() throws {
        let store = try CoffeeStore.inMemory()
        let brews = (1...12).map { i in
            bcBrew(["config": ["uuid": "brew-\(i)", "unix_timestamp": 1706788800 + i * 86_400], "rating": i % 2 == 0 ? 4 : 0])
        }
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()], brews: brews), timeZone: utc))

        let recent = try store.recentBrews(beanID: "uuid-1")
        #expect(recent.count == 10)
        #expect(recent.first?.creationDate == "2024-02-13")
        #expect(recent.first?.rating == 4)
        #expect(recent[1].rating == nil)
        #expect(recent.last?.creationDate == "2024-02-04")
    }

    @Test func freezeEventsOldestFirst() throws {
        let store = try CoffeeStore.inMemory()
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()]), timeZone: utc))
        try store.db.execute("""
            INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('uuid-1', 'thaw', '2026-02-10');
            INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('uuid-1', 'freeze', '2026-01-20');
            """)
        #expect(try store.freezeEvents(beanID: "uuid-1") == [
            FreezeEvent(kind: .freeze, date: "2026-01-20"),
            FreezeEvent(kind: .thaw, date: "2026-02-10"),
        ])
    }
}
