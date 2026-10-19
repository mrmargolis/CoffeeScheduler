import Testing

@testable import CoffeeCore

@Suite struct BagLabelDateTests {
    private let today = "2026-10-19"

    private func date(_ text: String, standalone: Bool = false) -> String? {
        BagLabel.date(in: text, today: today, standalone: standalone)
    }

    @Test func readsDatesWithTheMonthsName() {
        #expect(date("ROASTED ON AUGUST 5 2026") == "2026-08-05")
        #expect(date("Roasted Oct 3") == "2026-10-03")
        #expect(date("roasted: 3rd October 2026") == "2026-10-03")
        #expect(date("Sept. 28, '26") == "2026-09-28")
        #expect(date("12 Dec") == "2025-12-12")  // Not yet this year, so last year's
    }

    @Test func readsNumericDates() {
        #expect(date("2026-10-12") == "2026-10-12")
        #expect(date("Roast date 10/12/26") == "2026-10-12")  // Month first, as US labels have it
        #expect(date("12.10.2026") == "2026-10-12")  // Day first with dots
        #expect(date("19/09/2026") == "2026-09-19")  // Only a day can be 19
        #expect(date("9/19", standalone: true) == "2026-09-19")
    }

    @Test func doesntTakeAWeightOrAFutureDate() {
        #expect(date("NET WT. 125G / 4.4OZ") == nil)
        #expect(date("4.4", standalone: false) == nil)
        #expect(date("Best before 12/01/2027") == nil)
        #expect(date("1900 MASL") == nil)
        #expect(date("2/30/2026") == nil)
        #expect(date("Ruiru 11, SL28/34") == nil)
    }

    @Test func readsWeightsInGrams() {
        #expect(BagLabel.weight(in: "NET WT. 125G / 4.4OZ") == 125)
        #expect(BagLabel.weight(in: "Net Wt 12oz") == 340)
        #expect(BagLabel.weight(in: "250 grams") == 250)
        #expect(BagLabel.weight(in: "1kg") == 1000)
        #expect(BagLabel.weight(in: "2 lb") == 907)
        #expect(BagLabel.weight(in: "1900 MASL") == nil)
        #expect(BagLabel.weight(in: "Brew 15g to 250g water") == 250)  // The first in range: 15 g is too little for a bag
    }
}
