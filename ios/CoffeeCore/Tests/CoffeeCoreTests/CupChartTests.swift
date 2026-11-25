import Testing

@testable import CoffeeCore

@Suite struct CupChartTests {
    @Test func stopsRunEdgeToEdgeWithIdealInTheMiddle() {
        #expect(CupChart.stops == [0, 0.25, 0.5, 0.75, 1])
        #expect(CupChart.position(0) == CupChart.centre)
    }

    @Test(arguments: [
        (-2, CupChart.Mark.bar(from: 0, to: 0.5)),
        (-1, .bar(from: 0.25, to: 0.5)),
        (0, .onTarget),
        (1, .bar(from: 0.5, to: 0.75)),
        (2, .bar(from: 0.5, to: 1)),
    ])
    func barsRunFromTheCentreToTheRating(value: Int, mark: CupChart.Mark) {
        #expect(CupChart.mark(value) == mark)
    }

    @Test func notEvaluatedIsUnknownNotOnTarget() {
        #expect(CupChart.mark(nil) == .unknown)
    }

    @Test func outOfRangeRatingsStopAtTheEdge() {
        #expect(CupChart.mark(5) == .bar(from: 0.5, to: 1))
        #expect(CupChart.mark(-7) == .bar(from: 0, to: 0.5))
    }

    @Test func oneRowPerAttributeInOrder() {
        let rows = CupChart.rows([.sweetness: -1, .body: 0])
        #expect(rows.map(\.attribute) == SensoryAttribute.allCases)
        #expect(rows.map(\.mark) == [.unknown, .bar(from: 0.25, to: 0.5), .unknown, .unknown, .onTarget, .unknown])
        #expect(rows[1].label == "Slightly low")
        #expect(rows[0].label == "Not evaluated")
    }
}
