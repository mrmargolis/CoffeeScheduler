import Foundation
import Testing

@testable import CoffeeCore

@Suite struct BagLabelPickTests {
    private let today = "2026-10-26"

    @Test func knowsWhatALineLooksLikeItHolds() {
        #expect(BagLabel.likelyFields(in: "Roasted 14.10.26", today: today, monthFirst: false) == [.roastDate])
        #expect(BagLabel.likelyFields(in: "250 g", today: today) == [.weight])
        #expect(BagLabel.likelyFields(in: "Producer: Hambela Estate", today: today).contains(.producer))
        #expect(BagLabel.likelyFields(in: "Natural", today: today) == [.process])
    }

    @Test func picksWhatALineSaysTheFieldIs() {
        #expect(BagLabel.value(in: "Producer: Hambela Estate", for: .producer, today: today) == "Hambela Estate")
        #expect(BagLabel.value(in: "Roasted 14.10.26", for: .roastDate, today: today, monthFirst: false) == "2026-10-14")
        #expect(BagLabel.value(in: "NET WT 250G", for: .weight, today: today) == "250")
    }

    @Test func picksTheWholeLineForATextFieldItDoesntName() {
        #expect(BagLabel.value(in: "HAMBELA", for: .coffee, today: today) == BagLabel.tidy("HAMBELA"))
        #expect(BagLabel.value(in: "Peach, jasmine", for: .producer, today: today) == "Peach, jasmine")
    }

    @Test func hasNoDateOrWeightInALineWithout() {
        #expect(BagLabel.value(in: "HAMBELA", for: .roastDate, today: today) == nil)
        #expect(BagLabel.value(in: "HAMBELA", for: .weight, today: today) == nil)
    }

    @Test func placesALineFromTheTopLeft() {
        let line = BagLabel.Line("250 g", x: 0.25, y: 0.1, width: 0.5, height: 0.1)
        let frame = line.frame(width: 200, height: 400)
        #expect(frame.minX == 50 && frame.width == 100)
        #expect(abs(frame.minY - 320) < 0.001 && abs(frame.height - 40) < 0.001)
    }
}
