import Testing

@testable import CoffeeCore

@Suite struct BagLabelDateTests {
    private let today = "2026-10-19"

    private func date(_ text: String, standalone: Bool = false, monthFirst: Bool = true) -> String? {
        BagLabel.date(in: text, today: today, standalone: standalone, monthFirst: monthFirst)
    }

    @Test func readsDatesWithTheMonthsName() {
        #expect(date("ROASTED ON AUGUST 5 2026") == "2026-08-05")
        #expect(date("Roasted Oct 3") == "2026-10-03")
        #expect(date("roasted: 3rd October 2026") == "2026-10-03")
        #expect(date("Sept. 28, '26") == "2026-09-28")
        #expect(date("12 Dec") == "2025-12-12")  // Not yet this year, so last year's
        #expect(date("Batch P25Sep26-1") == "2026-09-25")  // GWO's batch codes: day, month, year, batch
        #expect(date("Roasted Sep 26") == "2026-09-26")
    }

    @Test func readsNumericDates() {
        #expect(date("2026-10-12") == "2026-10-12")
        #expect(date("Roast date 10/12/26") == "2026-10-12")  // Month first, as US labels have it
        #expect(date("12.10.2026", monthFirst: false) == "2026-10-12")  // Day first where the phone's region is
        #expect(date("10.08.26") == "2026-10-08")  // Dots in the US are month first too
        #expect(date("19/09/2026") == "2026-09-19")  // Only a day can be 19
        #expect(date("9/19", standalone: true) == "2026-09-19")
    }

    @Test func takesTheOnlyOrderThatsADayByToday() {
        // 10 December hasn't come yet, so these are October 12th
        #expect(date("10.12.26", monthFirst: false) == "2026-10-12")
        #expect(date("12/10/26", monthFirst: true) == "2026-10-12")
    }

    @Test func readsAnEitherWayDateInTheRegionsOrderAsAGuess() {
        let us = BagLabel.dated("10/08/26", today: today, standalone: true, monthFirst: true)
        #expect(us?.iso == "2026-10-08")
        #expect(us?.isGuess == true)
        let europe = BagLabel.dated("10/08/26", today: today, standalone: true, monthFirst: false)
        #expect(europe?.iso == "2026-08-10")
        #expect(BagLabel.dated("19/09/26", today: today, standalone: true, monthFirst: true)?.isGuess == false)
        #expect(BagLabel.dated("5/5/26", today: today, standalone: true, monthFirst: true)?.isGuess == false)  // The same either way
    }

    @Test func aLabelledEitherWayDateIsAGuess() {
        let either = BagLabel.labelled(["Roasted: 10.08.26"], today: today, monthFirst: true)
        #expect(either.roastDate == "2026-10-08")
        #expect(either.isGuess(.roastDate))
        let only = BagLabel.labelled(["Roasted: 19/09/26"], today: today, monthFirst: true)
        #expect(only.roastDate == "2026-09-19")
        #expect(!only.isGuess(.roastDate))
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
