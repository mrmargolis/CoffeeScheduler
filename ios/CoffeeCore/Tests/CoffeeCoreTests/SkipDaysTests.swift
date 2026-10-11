import Testing
@testable import CoffeeCore

// Ported from src/__tests__/api/skip-days.test.ts.
@Suite struct SkipDaysTests {
    let store: CoffeeStore

    init() throws {
        store = try CoffeeStore.inMemory()
    }

    func insertRange(_ start: String, _ end: String, reason: String? = nil) throws {
        try store.db.run(
            "INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)",
            [.text(start), .text(end), SQLValue(reason)]
        )
    }

    /// (start, end) of every range, earliest first.
    func ranges() throws -> [[String]] {
        try store.skipRanges(from: "0000-01-01").map { [$0.startDate, $0.endDate] }
    }

    // MARK: Toggle on

    @Test func toggleOnInsertsASingleDay() throws {
        #expect(try store.toggleSkipDay("2026-03-10") == true)
        #expect(try ranges() == [["2026-03-10", "2026-03-10"]])
    }

    @Test func toggleOnAfterARangeExtendsIt() throws {
        try insertRange("2026-03-10", "2026-03-12")
        #expect(try store.toggleSkipDay("2026-03-13") == true)
        #expect(try ranges() == [["2026-03-10", "2026-03-13"]])
    }

    @Test func toggleOnBeforeARangeExtendsIt() throws {
        try insertRange("2026-03-12", "2026-03-15")
        #expect(try store.toggleSkipDay("2026-03-11") == true)
        #expect(try ranges() == [["2026-03-11", "2026-03-15"]])
    }

    @Test func toggleOnBetweenTwoRangesBridgesThem() throws {
        try insertRange("2026-03-10", "2026-03-12")
        try insertRange("2026-03-14", "2026-03-16")
        #expect(try store.toggleSkipDay("2026-03-13") == true)
        #expect(try ranges() == [["2026-03-10", "2026-03-16"]])
    }

    @Test func toggleOnAcrossAMonthEnd() throws {
        try insertRange("2026-02-26", "2026-02-28")
        #expect(try store.toggleSkipDay("2026-03-01") == true)
        #expect(try ranges() == [["2026-02-26", "2026-03-01"]])
    }

    // MARK: Toggle off

    @Test func toggleOffASingleDayDeletesIt() throws {
        try insertRange("2026-03-10", "2026-03-10")
        #expect(try store.toggleSkipDay("2026-03-10") == false)
        #expect(try ranges().isEmpty)
    }

    @Test func toggleOffTheFirstDayShrinksFromTheStart() throws {
        try insertRange("2026-03-10", "2026-03-15", reason: "Trip")
        #expect(try store.toggleSkipDay("2026-03-10") == false)
        #expect(try ranges() == [["2026-03-11", "2026-03-15"]])
    }

    @Test func toggleOffTheLastDayShrinksFromTheEnd() throws {
        try insertRange("2026-03-10", "2026-03-15")
        #expect(try store.toggleSkipDay("2026-03-15") == false)
        #expect(try ranges() == [["2026-03-10", "2026-03-14"]])
    }

    @Test func toggleOffAMiddleDaySplitsKeepingTheReason() throws {
        try insertRange("2026-03-10", "2026-03-15", reason: "Vacation")
        #expect(try store.toggleSkipDay("2026-03-12") == false)
        let split = try store.skipRanges(from: "2026-01-01")
        #expect(split.map { [$0.startDate, $0.endDate] } == [["2026-03-10", "2026-03-11"], ["2026-03-13", "2026-03-15"]])
        #expect(split.map(\.reason) == ["Vacation", "Vacation"])
    }

    @Test func toggleTwiceRestoresTheRange() throws {
        try insertRange("2026-03-10", "2026-03-15")
        try store.toggleSkipDay("2026-03-12")
        try store.toggleSkipDay("2026-03-12")
        #expect(try ranges() == [["2026-03-10", "2026-03-15"]])
    }

    // MARK: Listing, deleting, and the schedule

    @Test func listingLeavesOutRangesThatAlreadyEnded() throws {
        try insertRange("2026-02-01", "2026-02-03")
        try insertRange("2026-03-01", "2026-03-05")
        try insertRange("2026-04-01", "2026-04-02")
        #expect(try store.skipRanges(from: "2026-03-05").map(\.startDate) == ["2026-03-01", "2026-04-01"])
    }

    @Test func deleteRemovesSkipsFromTheSchedule() throws {
        try store.db.run(
            "INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived) VALUES ('b1', 'Bean', 'Roaster', '2026-01-01', 250, 0)"
        )
        try insertRange("2026-02-01", "2026-02-02")
        var schedule = try store.schedule(start: "2026-01-31", end: "2026-02-04", today: "2026-01-01")
        #expect(schedule.filter(\.isSkip).map(\.date) == ["2026-02-01", "2026-02-02"])

        try store.deleteSkipRange(id: try #require(store.skipRanges(from: "2026-01-01").first).id)
        schedule = try store.schedule(start: "2026-01-31", end: "2026-02-04", today: "2026-01-01")
        #expect(schedule.filter(\.isSkip).isEmpty)
    }

    @Test func toggledDayIsSkippedAndConsumptionMoves() throws {
        try store.db.run(
            "INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived) VALUES ('b1', 'Bean', 'Roaster', '2026-01-01', 250, 0)"
        )
        try store.toggleSkipDay("2026-02-02")
        let schedule = try store.schedule(start: "2026-02-01", end: "2026-02-03", today: "2026-01-01")
        let day = try #require(schedule.first { $0.date == "2026-02-02" })
        #expect(day.isSkip)
        #expect(day.consumptions.isEmpty)
        #expect(schedule.first { $0.date == "2026-02-03" }?.consumptions.isEmpty == false)
    }
}
