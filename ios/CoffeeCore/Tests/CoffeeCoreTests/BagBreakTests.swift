import Testing

@testable import CoffeeCore

/// Breaks in a bag without freezing it: the rest of the bag waits at its own
/// place in the queue.
@Suite struct BagBreakTests {
    /// An opened bag, ready, with breaks, then two full bags, all in
    /// automatic order: the opened one first.
    private func bags(remaining: Double, breaks: [BagBreak], others: Int = 2) -> [Scheduler.Bean] {
        var gwo = makeBean(id: "gwo", roastDate: "2025-11-20", remainingGrams: remaining)
        gwo.breaks = breaks
        let full = [
            makeBean(id: "other", roastDate: "2025-11-25"),
            makeBean(id: "third", roastDate: "2025-11-28"),
        ]
        return [gwo] + full.prefix(others)
    }

    /// A break at `grams`, queued after the next bag.
    private func pause(_ grams: Double, id: Int = 1, order: Int? = nil) -> BagBreak {
        BagBreak(id: id, afterGrams: grams, displayOrder: order)
    }

    /// The days, from the first, that `id` is drunk on.
    private func days(of id: String, in days: [ScheduleDay]) -> [Int] {
        days.enumerated().filter { $0.element.consumptions.contains { $0.beanID == id } }.map(\.offset)
    }

    private func grams(where matches: (Consumption) -> Bool, in days: [ScheduleDay]) -> Double {
        days.flatMap(\.consumptions).filter(matches).reduce(0) { $0 + $1.grams }
    }

    // MARK: - The queue

    private func queue(_ beans: [Scheduler.Bean]) -> [String] {
        Scheduler.queue(beans).map(\.id)
    }

    @Test func queuesTheRestAfterTheNextBag() {
        #expect(queue(bags(remaining: 150, breaks: [pause(150)])) == ["gwo", "other", "break:1", "third"])
    }

    @Test func queuesTheRestWhereItsBeenPut() {
        var beans = bags(remaining: 150, breaks: [pause(150, order: 4)])
        for (i, id) in ["gwo", "other", "third"].enumerated() { beans[beans.firstIndex { $0.id == id }!].displayOrder = i + 1 }
        #expect(queue(beans) == ["gwo", "other", "third", "break:1"])
    }

    @Test func keepsTheRestBelowItsBag() {
        // Numbered above the bag, as an older build's renumbering could leave it
        var beans = bags(remaining: 150, breaks: [pause(150, order: 1)])
        for (i, id) in ["gwo", "other", "third"].enumerated() { beans[beans.firstIndex { $0.id == id }!].displayOrder = i + 2 }
        #expect(queue(beans) == ["gwo", "other", "break:1", "third"])
    }

    @Test func queuesEachRestAfterTheOneBefore() {
        let beans = bags(remaining: 150, breaks: [pause(200, id: 2), pause(150, id: 1)])
        #expect(queue(beans) == ["gwo", "other", "break:1", "third", "break:2"])
    }

    @Test func listsABagOnItsBreakAtTheRestsPlace() {
        // Drunk to the 150 g break, so the bag waits where its rest is
        #expect(queue(bags(remaining: 100, breaks: [pause(150)])) == ["other", "break:1", "third"])
    }

    @Test func movesARestDraggedAboveItsBagBelowIt() {
        let parts = Scheduler.queue(bags(remaining: 150, breaks: [pause(150)]))
        #expect(Scheduler.keepingPartsInOrder(["break:1", "other", "gwo", "third"], parts: parts) == ["other", "gwo", "break:1", "third"])
        #expect(Scheduler.keepingPartsInOrder(["gwo", "third", "break:1", "other"], parts: parts) == ["gwo", "third", "break:1", "other"])
    }

    @Test func readsARestsKey() {
        #expect(QueuePart<Bean>.key(breakID: 7) == "break:7")
        #expect(QueuePart<Bean>.breakID(in: "break:7") == 7)
        #expect(QueuePart<Bean>.breakID(in: "uuid-1") == nil)
    }

    // MARK: - The bag's part

    private func part(used: Double, breaks: [BagBreak]) -> QueuePart<Bean> {
        var bean = makeDetailBean(totalBrewedGrams: used)
        bean.breaks = breaks
        return Scheduler.currentPart(of: bean)
    }

    @Test func knowsWhichPartTheBagIsIn() {
        #expect(part(used: 100, breaks: [pause(150)]).index == 0)
        // Within a dose of the break counts as there: the schedule won't take less
        #expect(part(used: 135, breaks: [pause(150)]).index == 0)
        #expect(part(used: 137, breaks: [pause(150)]).index == 1)
        #expect(part(used: 160, breaks: [pause(150), pause(200, id: 2)]).index == 1)
        #expect(part(used: 245, breaks: [pause(150), pause(200, id: 2)]).index == 2)
    }

    @Test func isOnTheBreakUntilTheRestIsStarted() {
        #expect(!part(used: 150, breaks: [pause(150)]).isStarted)
        #expect(part(used: 160, breaks: [pause(150)]).isStarted)
        #expect(part(used: 100, breaks: [pause(150)]).isStarted)
    }

    @Test func givesThePartsSizes() {
        let rest = part(used: 160, breaks: [pause(150), pause(200, id: 2)])
        #expect(rest.startGrams == 150)
        #expect(rest.endGrams == 200)
        #expect(rest.leftGrams == 40)
    }

    // MARK: - The schedule

    @Test func drinksDownToTheBreakThenTheNextBagThenTheRest() {
        // 50 g to the break: a day of it, then 250 g of the next bag, then the rest
        let result = schedule("2026-01-01", "2026-01-12", beans: bags(remaining: 150, breaks: [pause(150)]))
        #expect(days(of: "gwo", in: result).first == 0)
        #expect(days(of: "other", in: result) == Array(1...6))
        #expect(Scheduler.partRuns(result)["break:1"]?.start == "2026-01-07")
        #expect(days(of: "gwo", in: result).first(where: { $0 > 0 }) == 6)
        #expect(days(of: "third", in: result).first == 8)
        #expect(result.allSatisfy { !$0.isGap })
    }

    @Test func comesBackLaterForARestPutLower() {
        var beans = bags(remaining: 150, breaks: [pause(150, order: 4)])
        for (i, id) in ["gwo", "other", "third"].enumerated() { beans[beans.firstIndex { $0.id == id }!].displayOrder = i + 1 }
        let result = schedule("2026-01-01", "2026-01-20", beans: beans)
        let back = Scheduler.partRuns(result)["break:1"]?.start
        // Taken up on the day the third bag runs out, after it
        #expect(back == "2026-01-12")
        #expect(Scheduler.finishDates(result)["third"] == back)
        #expect(result[11].consumptions.map(\.beanID) == ["third", "gwo"])
    }

    @Test func keepsWhatsLeftAtTheBreakForTheRest() {
        // 40 g to go before the break: two doses, and the 10 g over waits for the rest
        let result = schedule("2026-01-01", "2026-01-20", beans: bags(remaining: 140, breaks: [pause(150)]))
        #expect(grams(where: { $0.beanID == "gwo" && $0.partID == nil }, in: result) == 30)
        #expect(grams(where: { $0.partID == "break:1" }, in: result) == 105)
    }

    @Test func passesTheBagByWithLessThanADoseBeforeTheBreak() {
        // 13 g above the break: not a whole dose, so the bag rests and isn't counted ready
        let result = schedule("2026-01-01", "2026-01-03", beans: bags(remaining: 113, breaks: [pause(150)], others: 1))
        #expect(!days(of: "gwo", in: result).contains(0))
        #expect(!result[0].isSurplus)
    }

    @Test func takesNoPartDoseBeforeTheBreakOnASmallDay() {
        // A 13 g day: the 13 g above the break would cover it, but isn't a dose
        let result = schedule(
            "2026-01-01", "2026-01-01", beans: bags(remaining: 113, breaks: [pause(150)]),
            overrides: ["2026-01-01": Scheduler.DayOverride(dailyGrams: 13, doseSize: 15)])
        #expect(result[0].consumptions.map(\.beanID) == ["other"])
    }

    @Test func doesntCountABagOnABreakAsReady() {
        // Drunk to the break: 150 g used
        let result = schedule("2026-01-01", "2026-01-03", beans: bags(remaining: 100, breaks: [pause(150)], others: 1))
        #expect(result.allSatisfy { !$0.isSurplus })
    }

    @Test func countsARestTakenUpAgainAsReady() {
        // 160 g used, back from the break: ready alongside the other bag
        var beans = bags(remaining: 90, breaks: [pause(150, order: 1)], others: 1)
        beans[1].displayOrder = 2
        let result = schedule("2026-01-01", "2026-01-01", beans: beans)
        #expect(result[0].isSurplus)
    }

    @Test func takesSeveralBreaksInTurn() {
        // A full bag: to 100 g (two days, the 10 g over kept), the next bag, to
        // 175 g, the third, then the rest
        var beans = bags(remaining: 250, breaks: [pause(175, id: 2), pause(100, id: 1)])
        beans[0].displayOrder = 1
        let result = schedule("2026-01-01", "2026-01-25", beans: beans)
        let runs = Scheduler.partRuns(result)
        let firstPart = days(of: "gwo", in: result).filter { result[$0].consumptions.contains { $0.beanID == "gwo" && $0.partID == nil } }
        #expect(firstPart == [0, 1])
        #expect(Scheduler.finishDates(result)["other"]! <= runs["break:1"]!.start)
        #expect(runs["break:1"]!.end <= Scheduler.startDates(result)["third"]!)
        #expect(Scheduler.finishDates(result)["third"]! <= runs["break:2"]!.start)
    }

    @Test func aBreakAndAFreezeTogetherStopAtTheFirstOfThem() {
        var gwo = makeBean(id: "gwo", roastDate: "2025-11-20", freezeAfterGrams: 100)
        gwo.breaks = [pause(150)]
        let result = schedule("2026-01-01", "2026-01-10", beans: [gwo, makeBean(id: "other", roastDate: "2025-11-25")])
        #expect(grams(where: { $0.beanID == "gwo" }, in: result) == 90)
    }

    @Test func skipsPutTheRestBackByAsManyDays() {
        let result = schedule(
            "2026-01-01", "2026-01-15", beans: bags(remaining: 150, breaks: [pause(150)]),
            skipDays: ["2026-01-03", "2026-01-04", "2026-01-05"])
        #expect(Scheduler.partRuns(result)["break:1"]?.start == "2026-01-10")
    }

    // MARK: - Saving

    /// Three bags, uuid-1 to uuid-3, roasted a day apart.
    private func storeWithBags() throws -> CoffeeStore {
        let store = try CoffeeStore.inMemory()
        let beans = (1...3).map { n in
            bcBean([
                "name": "Bag \(n)", "roastingDate": "2026-01-1\(n)T00:00:00.000Z", "config": ["uuid": "uuid-\(n)", "unix_timestamp": 1_700_000_000],
            ])
        }
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: beans), timeZone: utc), on: "2026-02-01")
        return store
    }

    private func breaks(_ store: CoffeeStore) throws -> [BagBreak] {
        try store.bean(id: "uuid-1")?.breaks ?? []
    }

    @Test func addsChangesAndEndsBreaks() throws {
        let store = try storeWithBags()
        let later = try store.addBreak(beanID: "uuid-1", afterGrams: 200)
        let sooner = try store.addBreak(beanID: "uuid-1", afterGrams: 100)
        #expect(try breaks(store) == [pause(100, id: sooner), pause(200, id: later)])

        try store.updateBreak(id: sooner, afterGrams: 120)
        #expect(try breaks(store).map(\.afterGrams) == [120, 200])
        try store.deleteBreak(id: later)
        #expect(try breaks(store) == [pause(120, id: sooner)])
    }

    @Test func refusesABreakThatLeavesNothingOnOneSideOrDoublesOne() throws {
        let store = try storeWithBags()
        for grams in [0.0, 250, 300] {
            #expect(throws: BreakError.outOfRange(weightGrams: 250)) { try store.addBreak(beanID: "uuid-1", afterGrams: grams) }
        }
        let id = try store.addBreak(beanID: "uuid-1", afterGrams: 100)
        #expect(throws: BreakError.alreadyThere) { try store.addBreak(beanID: "uuid-1", afterGrams: 100) }
        #expect(throws: BreakError.notFound) { try store.addBreak(beanID: "nope", afterGrams: 100) }
        #expect(throws: BreakError.notFound) { try store.updateBreak(id: id + 1, afterGrams: 100) }
        // Its own grams again is no clash
        try store.updateBreak(id: id, afterGrams: 100)
    }

    @Test func ordersRestsWithTheBags() throws {
        let store = try storeWithBags()
        let id = try store.addBreak(beanID: "uuid-1", afterGrams: 100)
        let rest = QueuePart<Bean>.key(breakID: id)
        try store.moveInQueue(["uuid-1", "uuid-2", "uuid-3", rest], moved: rest)
        #expect(try breaks(store).first?.displayOrder == 4)
        #expect(try store.bean(id: "uuid-3")?.displayOrder == 3)

        // Back to after the next bag, then the whole queue to automatic
        try store.clearQueuePosition(id: rest)
        #expect(try breaks(store).first?.displayOrder == nil)
        try store.moveInQueue([rest, "uuid-1"], moved: rest)
        try store.clearQueueOrder()
        #expect(try breaks(store).first?.displayOrder == nil)
        #expect(try store.bean(id: "uuid-1")?.displayOrder == nil)
    }

    @Test func endingABreakRenumbersTheQueue() throws {
        let store = try storeWithBags()
        let id = try store.addBreak(beanID: "uuid-1", afterGrams: 100)
        try store.reorderQueue(["uuid-1", QueuePart<Bean>.key(breakID: id), "uuid-2"])
        try store.deleteBreak(id: id)
        #expect(try store.bean(id: "uuid-2")?.displayOrder == 2)
    }

    @Test func schedulesTheSavedBreaks() throws {
        let store = try storeWithBags()
        try store.addBreak(beanID: "uuid-1", afterGrams: 90)
        let days = try store.schedule(start: "2026-02-01", end: "2026-02-12", today: "2026-02-01")
        // Two days to 90 g, then Bag 2, then the rest
        #expect(self.days(of: "uuid-1", in: days).prefix(3) == [0, 1, 7])
        #expect(self.days(of: "uuid-2", in: days).first == 2)
    }

    @Test func keepsBreaksMadeWithADayToComeBack() throws {
        // A file from the build that gave each break a day
        let db = try SQLiteDatabase(path: ":memory:")
        _ = try CoffeeStore(db: db)
        try db.execute(
            """
            INSERT INTO beans (id, name, weight_grams) VALUES ('old', 'Old Bean', 250);
            CREATE TABLE bag_breaks (
              id INTEGER PRIMARY KEY AUTOINCREMENT, bean_id TEXT NOT NULL REFERENCES beans(id),
              after_grams REAL NOT NULL, resume_date TEXT NOT NULL
            );
            INSERT INTO bag_breaks (bean_id, after_grams, resume_date) VALUES ('old', 150, '2026-03-01');
            """)

        let store = try CoffeeStore(db: db)
        #expect(try store.bean(id: "old")?.breaks.map(\.afterGrams) == [150])
        #expect(try db.query("SELECT name FROM sqlite_master WHERE name = 'bag_breaks'").isEmpty)
    }
}
