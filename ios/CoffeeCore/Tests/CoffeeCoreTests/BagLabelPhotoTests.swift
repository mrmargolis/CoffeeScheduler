import Testing

@testable import CoffeeCore

/// Labels from real bags: each line's text, and roughly where it sits in
/// the photo, as Vision reads it.
enum LabelPhotos {
    /// A line measured from the photo's top left, as fractions of its size.
    static func line(_ text: String, left: Double, top: Double, width: Double, height: Double) -> BagLabel.Line {
        BagLabel.Line(text, x: left, y: 1 - top - height, width: width, height: height)
    }

    /// A sticker, with the roaster's script logo beside the name and
    /// "Coffee" under it.
    static let gwo = [
        line("Gititu AB #007", left: 0.267, top: 0.635, width: 0.167, height: 0.02),
        line("gwo", left: 0.63, top: 0.64, width: 0.1, height: 0.025),
        line("Kenya", left: 0.267, top: 0.665, width: 0.053, height: 0.017),
        line("Coffee", left: 0.68, top: 0.67, width: 0.042, height: 0.011),
        line("Ruiru 11, SL28/34, Batian Washed", left: 0.267, top: 0.69, width: 0.36, height: 0.019),
        line("Rhubarb, cranberry, hibiscus", left: 0.267, top: 0.725, width: 0.28, height: 0.017),
    ]

    /// The roaster's name biggest of all, at the bottom.
    static let delicate = [
        line("golden raspberry · lemon sugar · lilac", left: 0.32, top: 0.26, width: 0.46, height: 0.017),
        line("bare - special prep", left: 0.41, top: 0.31, width: 0.37, height: 0.03),
        line("bona zuria, sidama, ethiopia", left: 0.43, top: 0.35, width: 0.35, height: 0.017),
        line("mixed JARC | white honey", left: 0.48, top: 0.375, width: 0.3, height: 0.017),
        line("ayele tulu & family", left: 0.54, top: 0.4, width: 0.24, height: 0.017),
        line("delicate", left: 0.49, top: 0.81, width: 0.27, height: 0.05),
        line("coffee roasters", left: 0.54, top: 0.875, width: 0.27, height: 0.025),
    ]

    /// A small printed sticker over a big logo, with the edge of another
    /// bag in the photo.
    static let lume = [
        line("Danche | Ethiopia", left: 0.345, top: 0.265, width: 0.18, height: 0.017),
        line("Landrace | Washed", left: 0.345, top: 0.282, width: 0.2, height: 0.017),
        line("al, Coriander", left: 0.91, top: 0.29, width: 0.09, height: 0.015),
        line("Apricot, Melon, Pineapple, Floral", left: 0.34, top: 0.3, width: 0.35, height: 0.018),
        line("Roast", left: 0.91, top: 0.32, width: 0.05, height: 0.014),
        line("9/19", left: 0.34, top: 0.32, width: 0.04, height: 0.015),
        line("LUME", left: 0.43, top: 0.53, width: 0.31, height: 0.07),
        line("COFFEE ROASTERS", left: 0.46, top: 0.645, width: 0.25, height: 0.014),
        line("E RO", left: 0.94, top: 0.645, width: 0.06, height: 0.012),
    ]

    /// The logo in the middle; the name on a band with the origin, variety
    /// and process running up its side.
    static let septemberPepe = [
        line("SEPTEMBER", left: 0.34, top: 0.575, width: 0.39, height: 0.04),
        line("COFFEE CO.", left: 0.46, top: 0.635, width: 0.17, height: 0.02),
        line("Ecuador", left: 0.055, top: 0.775, width: 0.02, height: 0.07),
        line("Mejorado", left: 0.1, top: 0.77, width: 0.02, height: 0.08),
        line("Rainbow Wave", left: 0.155, top: 0.77, width: 0.02, height: 0.12),
        line("Pepe Jijon", left: 0.69, top: 0.8, width: 0.18, height: 0.022),
        line("Green Apple, White Florals, Marshmallow", left: 0.24, top: 0.84, width: 0.38, height: 0.014),
    ]

    static let septemberHanan = [
        line("SEPTEMBER", left: 0.34, top: 0.565, width: 0.38, height: 0.04),
        line("COFFEE CO.", left: 0.45, top: 0.625, width: 0.17, height: 0.02),
        line("Ethiopia", left: 0.025, top: 0.81, width: 0.02, height: 0.07),
        line("Landrace", left: 0.075, top: 0.8, width: 0.02, height: 0.08),
        line("Natural", left: 0.125, top: 0.8, width: 0.02, height: 0.06),
        line("Hanan Million", left: 0.58, top: 0.78, width: 0.22, height: 0.022),
        line("Dried Fig, Blueberry, Black Tea", left: 0.29, top: 0.83, width: 0.27, height: 0.012),
    ]

    /// The name in two lines of capitals; the roaster in a small round logo,
    /// its words on separate lines.
    static let hAndS = [
        line("HUILA, COLOMBIA", left: 0.12, top: 0.12, width: 0.22, height: 0.015),
        line("LA FORTUNA", left: 0.12, top: 0.14, width: 0.27, height: 0.028),
        line("PINK BOURBON", left: 0.12, top: 0.172, width: 0.33, height: 0.028),
        line("H&S", left: 0.56, top: 0.18, width: 0.12, height: 0.028),
        line("COFFEE", left: 0.56, top: 0.205, width: 0.05, height: 0.008),
        line("ROASTERS", left: 0.56, top: 0.214, width: 0.07, height: 0.008),
        line("WHITE PEACH / STARFRUIT / ORANGE BLOSSOM", left: 0.12, top: 0.225, width: 0.42, height: 0.014),
        line("PINK BOURBON / WASHED / ULTRALIGHT", left: 0.12, top: 0.245, width: 0.36, height: 0.014),
        line("WHOLE BEAN COFFEE ROASTED IN LARAMIE WY 82070", left: 0.12, top: 0.265, width: 0.48, height: 0.014),
        line("NET WT. 125G / 4.4OZ", left: 0.1, top: 0.94, width: 0.2, height: 0.014),
        line("ROASTED ON AUGUST 5 2026", left: 0.1, top: 0.965, width: 0.28, height: 0.014),
    ]
}

@Suite struct BagLabelPhotoTests {
    private typealias Reading = BagLabel.Reading

    @Test func readsANameBesideAScriptLogo() {
        #expect(BagLabel.read(LabelPhotos.gwo, knownRoasters: []) == Reading(roaster: "gwo Coffee", coffee: "Gititu AB #007"))
    }

    @Test func readsANameWhenTheRoastersNameIsTheBiggestText() {
        #expect(
            BagLabel.read(LabelPhotos.delicate, knownRoasters: [])
                == Reading(roaster: "delicate coffee roasters", coffee: "bare - special prep"))
    }

    @Test func takesTheNameFromBesideItsOrigin() {
        #expect(BagLabel.read(LabelPhotos.lume, knownRoasters: []) == Reading(roaster: "LUME COFFEE ROASTERS", coffee: "Danche"))
    }

    @Test func leavesOutTextRunningUpTheSide() {
        #expect(
            BagLabel.read(LabelPhotos.septemberPepe, knownRoasters: [])
                == Reading(roaster: "SEPTEMBER COFFEE CO.", coffee: "Pepe Jijon"))
        #expect(
            BagLabel.read(LabelPhotos.septemberHanan, knownRoasters: [])
                == Reading(roaster: "SEPTEMBER COFFEE CO.", coffee: "Hanan Million"))
    }

    @Test func joinsANameOnTwoLinesAndClimbsALogosWords() {
        #expect(
            BagLabel.read(LabelPhotos.hAndS, knownRoasters: [])
                == Reading(roaster: "H&S COFFEE ROASTERS", coffee: "LA FORTUNA PINK BOURBON"))
    }

    @Test func givesAKnownRoasterItsNameInTheApp() {
        let known = ["Delicate Coffee Roasters", "GWO Coffee", "H&S Coffee Roasters", "Lume Coffee", "September Coffee Co", "Sey"]
        #expect(BagLabel.read(LabelPhotos.gwo, knownRoasters: known).roaster == "GWO Coffee")
        #expect(BagLabel.read(LabelPhotos.delicate, knownRoasters: known).roaster == "Delicate Coffee Roasters")
        #expect(BagLabel.read(LabelPhotos.lume, knownRoasters: known) == Reading(roaster: "Lume Coffee", coffee: "Danche"))
        #expect(BagLabel.read(LabelPhotos.septemberPepe, knownRoasters: known).roaster == "September Coffee Co")
        #expect(BagLabel.read(LabelPhotos.hAndS, knownRoasters: known).roaster == "H&S Coffee Roasters")
    }

    @Test func keepsTheModelsReadingWhereItHoldsUp() {
        let guess = BagLabel.read(LabelPhotos.hAndS, knownRoasters: [])
        let model = Reading(roaster: "H&S Coffee Roasters", coffee: "La Fortuna Pink Bourbon")
        #expect(BagLabel.checked(model, guess: guess, lines: LabelPhotos.hAndS, knownRoasters: []) == model)
    }

    @Test func rejectsAModelCoffeeThatIsntAName() {
        let guess = BagLabel.read(LabelPhotos.gwo, knownRoasters: [])
        for coffee in ["Kenya", "Rhubarb, cranberry, hibiscus", "gwo", "Gititu Estate"] {
            let checked = BagLabel.checked(Reading(roaster: "gwo", coffee: coffee), guess: guess, lines: LabelPhotos.gwo, knownRoasters: [])
            #expect(checked.coffee == "Gititu AB #007", "\(coffee)")
        }
    }

    @Test func rejectsAModelCoffeeWithTastingNotesInIt() {
        let guess = BagLabel.read(LabelPhotos.delicate, knownRoasters: [])
        for coffee in ["bare - special prep, golden raspberry", "Bare Special Prep Lemon Sugar Lilac"] {
            let model = Reading(roaster: "delicate coffee roasters", coffee: coffee)
            let checked = BagLabel.checked(model, guess: guess, lines: LabelPhotos.delicate, knownRoasters: [])
            #expect(checked.coffee == "bare - special prep", "\(coffee)")
        }
    }

    @Test func rejectsAModelRoasterThatIsntOnTheLabel() {
        let guess = BagLabel.read(LabelPhotos.lume, knownRoasters: [])
        let checked = BagLabel.checked(Reading(roaster: "Onyx", coffee: ""), guess: guess, lines: LabelPhotos.lume, knownRoasters: [])
        #expect(checked == guess)
    }

    @Test func rejectsAModelRoasterThatsOnlyCoffeeRoasters() {
        let guess = BagLabel.read(LabelPhotos.lume, knownRoasters: [])
        let model = Reading(roaster: "COFFEE ROASTERS", coffee: "Danche")
        let checked = BagLabel.checked(model, guess: guess, lines: LabelPhotos.lume, knownRoasters: [])
        #expect(checked.roaster == "LUME COFFEE ROASTERS")
    }

    @Test func keepsAKnownRoastersNameOverTheModels() {
        let known = ["September Coffee Co"]
        let guess = BagLabel.read(LabelPhotos.septemberPepe, knownRoasters: known)
        let model = Reading(roaster: "SEPTEMBER", coffee: "Pepe Jijon")
        #expect(
            BagLabel.checked(model, guess: guess, lines: LabelPhotos.septemberPepe, knownRoasters: known)
                == Reading(roaster: "September Coffee Co", coffee: "Pepe Jijon"))
    }

    @Test func promptsTopToBottomWithSizes() {
        let prompt = BagLabel.prompt(for: LabelPhotos.delicate, knownRoasters: ["Sey"])
        #expect(prompt.contains("Roasters the user has bought from before: Sey."))
        #expect(prompt.hasSuffix("[small] ayele tulu & family\n[big] delicate\n[medium] coffee roasters"))
        #expect(prompt.contains("\n\n[small] golden raspberry · lemon sugar · lilac\n[medium] bare - special prep\n"))
    }
}
