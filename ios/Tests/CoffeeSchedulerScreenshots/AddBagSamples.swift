import CoffeeCore
import UIKit

@testable import CoffeeScheduler

/// Add a bag part way through: the front and back of a label read, then
/// the coffee's page.
@MainActor
enum AddBagSamples {
    static func photos() -> BagIntake {
        let intake = BagIntake()
        intake.fill(
            draft([
                (.coffee, "Hambela Natural", .guessed), (.roaster, "Coffee Collective", .guessed),
                (.country, "Ethiopia", .stated), (.region, "Guji", .stated), (.process, "Natural", .stated),
            ]),
            from: .photo(label(), lines: ["COFFEE COLLECTIVE", "HAMBELA", "NATURAL", "ETHIOPIA · GUJI"]))
        intake.fill(
            draft([
                (.roastDate, "2026-10-14", .stated), (.weight, "250", .stated),
                (.notes, "Peach, jasmine, black tea", .stated), (.producer, "Hambela Estate", .guessed),
            ]),
            from: .photo(label(), lines: ["Peach, jasmine, black tea", "Producer: Hambela Estate", "Roasted 14.10.26", "250 g"]))
        return intake
    }

    /// The page confirms the coffee and roaster, adds the variety and link,
    /// and replaces the region.
    static func photosAndPage() -> BagIntake {
        let intake = photos()
        intake.fill(
            draft([
                (.coffee, "Hambela Natural", .stated), (.roaster, "Coffee Collective", .stated),
                (.region, "Guji Zone", .stated), (.variety, "Heirloom", .stated),
                (.url, "https://coffeecollective.dk/hambela", .stated),
            ]),
            from: .page(host: "coffeecollective.dk"))
        return intake
    }

    private static func draft(_ values: [(BagField, String, Certainty)]) -> BagDraft {
        var draft = BagDraft()
        for (field, text, certainty) in values {
            draft.restore(text, in: field)
            draft.certainty[field] = certainty
        }
        return draft
    }

    /// A stand-in for a photo of a label: a pale bag on a dark ground.
    private static func label() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 52, height: 60)).image { context in
            UIColor(red: 0.08, green: 0.07, blue: 0.05, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 52, height: 60))
            UIColor(red: 0.85, green: 0.78, blue: 0.65, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 8, y: 6, width: 36, height: 60), cornerRadius: 6).fill()
        }
    }
}
