import CoffeeCore
import SwiftUI
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
            from: photo(["COFFEE COLLECTIVE", "HAMBELA", "NATURAL", "ETHIOPIA · GUJI"]))
        intake.fill(
            draft([
                (.roastDate, "2026-10-14", .stated), (.weight, "250", .stated),
                (.notes, "Peach, jasmine, black tea", .stated), (.producer, "Hambela Estate", .guessed),
            ]),
            from: photo(["Peach, jasmine, black tea", "Producer: Hambela Estate", "Roasted 14.10.26", "250 g"]))
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
            from: .page(host: "coffeecollective.dk", lines: ["Hambela Natural", "Ethiopia · Guji Zone · Natural", "Variety: Heirloom"]))
        return intake
    }

    /// The front photo's text, ready to pick from.
    static func picker() -> some View {
        let intake = photos()
        return BagTextPicker(intake: intake, pick: TextPick(source: intake.sources[0].id, target: nil))
    }

    private static func photo(_ texts: [String]) -> BagSource.Kind {
        let lines = lines(texts)
        return .photo(label(lines), lines: lines)
    }

    /// Lines down the middle of the photo, top to bottom.
    private static func lines(_ texts: [String]) -> [BagLabel.Line] {
        texts.enumerated().map { index, text in
            BagLabel.Line(text, x: 0.15, y: 0.8 - Double(index) * 0.15, width: 0.7, height: 0.05)
        }
    }

    private static func draft(_ values: [(BagField, String, Certainty)]) -> BagDraft {
        var draft = BagDraft()
        for (field, text, certainty) in values {
            draft.restore(text, in: field)
            draft.certainty[field] = certainty
        }
        return draft
    }

    /// A stand-in for a photo of a label: a pale bag on a dark ground, with
    /// its lines printed where `lines` says they are.
    private static func label(_ lines: [BagLabel.Line]) -> UIImage {
        let size = CGSize(width: 600, height: 800)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.08, green: 0.07, blue: 0.05, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.85, green: 0.78, blue: 0.65, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 60, y: 40, width: 480, height: 800), cornerRadius: 40).fill()
            let ink: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30, weight: .bold),
                .foregroundColor: UIColor(red: 0.17, green: 0.13, blue: 0.09, alpha: 1),
            ]
            for line in lines {
                let frame = line.frame(width: size.width, height: size.height)
                (line.text as NSString).draw(in: frame, withAttributes: ink)
            }
        }
    }
}
