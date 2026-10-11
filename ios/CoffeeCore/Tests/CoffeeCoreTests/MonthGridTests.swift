import Testing

@testable import CoffeeCore

@Suite struct MonthGridTests {
    private func bean(_ id: String, _ start: String, _ end: String) -> CalendarEvent {
        CalendarEvent(kind: .bean(id: id, roaster: "Roaster"), title: id, start: start, end: end)
    }

    private func marker(_ kind: CalendarEvent.Kind, _ title: String, _ date: String) -> CalendarEvent {
        CalendarEvent(kind: kind, title: title, start: date, end: DateUtils.addDays(date, 1))
    }

    @Test func weekdaysCountFromMonday() {
        #expect(MonthGrid.weekdayIndex("2026-10-12") == 0)  // a Monday
        #expect(MonthGrid.weekdayIndex("2026-10-18") == 6)
        #expect(MonthGrid.weekdayIndex("1970-01-01") == 3)  // a Thursday
    }

    @Test func weeksCoverTheWholeMonth() {
        // October 2026 starts on a Thursday and ends on a Saturday
        #expect(
            MonthGrid.weeks(ofMonth: "2026-10-01") == ["2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26"]
        )
        // February 2027 is exactly four Monday-to-Sunday weeks
        #expect(MonthGrid.weeks(ofMonth: "2027-02-01").count == 4)
        // August 2026 starts on a Saturday and needs six
        #expect(MonthGrid.weeks(ofMonth: "2026-08-01").count == 6)
    }

    @Test func joinsNeighbouringSkipDaysIntoOneSpan() {
        let events = [
            marker(.skip, "Away", "2026-10-16"),
            bean("a", "2026-10-12", "2026-10-16"),
            marker(.skip, "Away", "2026-10-17"),
            marker(.skip, "Away", "2026-10-18"),
        ]
        let joined = MonthGrid.joined(events)
        #expect(joined.count == 2)
        #expect(joined[0].start == "2026-10-16" && joined[0].end == "2026-10-19")
        #expect(joined[1].beanID == "a")
    }

    @Test func keepsSeparateRunsAndDifferentReasonsApart() {
        let joined = MonthGrid.joined([
            marker(.skip, "Away", "2026-10-16"),
            marker(.skip, "Dentist", "2026-10-17"),
            marker(.skip, "Dentist", "2026-10-20"),
            marker(.gap, "No coffee", "2026-10-21"),
            marker(.gap, "No coffee", "2026-10-22"),
        ])
        #expect(joined.map(\.title) == ["Away", "Dentist", "Dentist", "No coffee"])
        #expect(joined[3].end == "2026-10-23")
    }

    @Test func clipsASpanToTheWeekAndMarksItsEnds() {
        // Wednesday of one week to Tuesday of the next (end is exclusive)
        let events = [bean("a", "2026-10-14", "2026-10-21")]

        let first = MonthGrid.segments(events, week: "2026-10-12")
        #expect(first.count == 1)
        #expect(first[0].startColumn == 2 && first[0].endColumn == 6)
        #expect(first[0].isStart && !first[0].isEnd)

        let second = MonthGrid.segments(events, week: "2026-10-19")
        #expect(second[0].startColumn == 0 && second[0].endColumn == 1)
        #expect(!second[0].isStart && second[0].isEnd)

        #expect(MonthGrid.segments(events, week: "2026-10-26").isEmpty)
    }

    @Test func stacksOverlappingSpansAndReusesAFreeLane() {
        let events = [
            bean("a", "2026-10-12", "2026-10-15"),
            bean("b", "2026-10-14", "2026-10-16"),
            bean("c", "2026-10-15", "2026-10-19"),
        ]
        let segments = MonthGrid.segments(events, week: "2026-10-12")
        #expect(segments.map(\.lane) == [0, 1, 0])
    }

    @Test func leavesOverrideMarkersOutOfTheBars() {
        let events = [marker(.override, "60 g/day", "2026-10-14"), marker(.gap, "No coffee", "2026-10-14")]
        #expect(MonthGrid.segments(events, week: "2026-10-12").map(\.event.kind) == [.gap])
    }

    @Test func snapshotSurvivesARoundTripThroughJSON() throws {
        let snapshot = WidgetSnapshot(
            events: [bean("a", "2026-10-12", "2026-10-15"), marker(.skip, "Away", "2026-10-16")],
            roasterColors: ["Roaster": "#4f7fd9"]
        )
        #expect(try WidgetSnapshot(decoding: snapshot.encoded()) == snapshot)
    }

    @Test func snapshotJoinsSkipDaysAndKeepsRoasterColours() {
        let schedule = ["2026-10-16", "2026-10-17"].map {
            ScheduleDay(date: $0, consumptions: [], isGap: false, isSurplus: false, isActual: false, isSkip: true)
        }
        let colors = RoasterColor.assign(["Square Mile"])
        let snapshot = WidgetSnapshot(schedule: schedule, skipRanges: [], roasterColors: colors)
        #expect(snapshot.events.count == 1)
        #expect(snapshot.events[0].end == "2026-10-18")
        #expect(snapshot.roasterColors["Square Mile"] == colors["Square Mile"]?.border)
    }
}
