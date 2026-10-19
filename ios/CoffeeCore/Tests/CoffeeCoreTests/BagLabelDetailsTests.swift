import Testing

@testable import CoffeeCore

@Suite struct BagLabelDetailsTests {
    private let today = "2026-10-19"

    private func details(_ lines: [BagLabel.Line]) -> BagDraft {
        BagLabel.details(in: lines, today: today)
    }

    /// Lines in reading order, as the app sorts them.
    private func text(_ lines: [String]) -> [BagLabel.Line] {
        lines.enumerated().map { BagLabel.Line($1, x: 0.1, y: 0.9 - Double($0) * 0.05, width: 0.5, height: 0.02) }
    }

    @Test func readsAFullLabel() {
        let draft = details(LabelPhotos.hAndS)
        #expect(draft.country == "Colombia")
        #expect(draft.region == "Huila")
        #expect(draft.variety == "Pink Bourbon")
        #expect(draft.process == "Washed")
        #expect(draft.notes == "White Peach, Starfruit, Orange Blossom")
        #expect(draft.weightGrams == 125)
        #expect(draft.roastDate == "2026-08-05")
    }

    @Test func readsTheOriginsListedTogether() {
        let gwo = details(LabelPhotos.gwo)
        #expect(gwo.country == "Kenya")
        #expect(gwo.variety == "Ruiru 11, SL28, Batian")
        #expect(gwo.process == "Washed")
        #expect(gwo.notes == "Rhubarb, cranberry, hibiscus")

        let delicate = details(LabelPhotos.delicate)
        #expect(delicate.country == "Ethiopia")
        #expect(delicate.region == "Sidama")
        #expect(delicate.variety == "JARC")
        #expect(delicate.process == "White Honey")
        #expect(delicate.notes == "golden raspberry, lemon sugar, lilac")
    }

    @Test func readsTextRunningUpTheSide() {
        let hanan = details(LabelPhotos.septemberHanan)
        #expect([hanan.country, hanan.variety, hanan.process] == ["Ethiopia", "Landrace", "Natural"])
        #expect(hanan.notes == "Dried Fig, Blueberry, Black Tea")
        let pepe = details(LabelPhotos.septemberPepe)
        #expect([pepe.country, pepe.variety, pepe.process] == ["Ecuador", "Mejorado", ""])
    }

    @Test func takesAStampedDateAndSkipsCutOffText() {
        let lume = details(LabelPhotos.lume)
        #expect(lume.roastDate == "2026-09-19")
        #expect(lume.notes == "Apricot, Melon, Pineapple, Floral")  // Not "al, Coriander" from the bag beside it
    }

    @Test func prefersWhatsLabelled() {
        let draft = details(
            text([
                "Ethiopia Guji", "Origin: Colombia", "Region: Huila", "Producer: Rodrigo Sánchez", "Variety: Java",
                "Process: Anaerobic Natural", "Notes: Grape, Cola", "Roasted on", "10/03/26", "Best before 04/03/27",
            ]))
        #expect(draft.country == "Colombia")
        #expect(draft.region == "Huila")
        #expect(draft.producer == "Rodrigo Sánchez")
        #expect(draft.variety == "Java")
        #expect(draft.process == "Anaerobic Natural")
        #expect(draft.notes == "Grape, Cola")
        #expect(draft.roastDate == "2026-10-03")
    }

    @Test func readsAProcessFromTheWordsAroundIt() {
        #expect(BagLabel.process(in: "Double Anaerobic Natural, Caturra") == "Double Anaerobic Natural")
        #expect(BagLabel.process(in: "White Florals, Green Apple") == nil)
    }

    @Test func readsOnlyWhatsLabelledOnAPage() {
        let page = """
            Shop
            Ethiopia
            Kenya
            Final Frontier
            Tasting notes: Apple, Blackberries, Plum
            Origin
            Honduras
            Region
            Santa Barbara
            Process: Natural. The cherries dry on raised beds for 30 days.
            Variety: Parainema
            Also try: Peach, Mango, Lychee
            """
        let draft = BagLabel.details(
            of: BagLabel.Page(
                heading: "Final Frontier\n", title: "Final Frontier – Proud Mary", site: "Proud Mary Coffee USA", text: page,
                url: "https://proudmary.example/ff"),
            knownRoasters: [], today: today)
        #expect(draft.coffee == "Final Frontier")
        #expect(draft.roaster == "Proud Mary Coffee USA")
        #expect(draft.url == "https://proudmary.example/ff")
        #expect(draft.notes == "Apple, Blackberries, Plum")
        #expect(draft.country == "Honduras")
        #expect(draft.region == "Santa Barbara")
        #expect(draft.process == "Natural")
        #expect(draft.variety == "Parainema")
    }
}

@Suite struct BagLabelPageTests {
    /// The text of Delicate's page for Suke Quto, as the browser gives it.
    private let sukeQuto = """
        shop
        archive
        suke quto
        125g |
        $19.00
        size
        125g
        250g
        1kg
        From : Suke Quto, Odo Shakisso, Guji, Ethiopia
        Varietal : Kurume, Welicho
        Process : Washed
        Producer: Tesfaye Bekele
        Notes : Yellow Peach, Bergamot, Dandelion
        whole coffee beans
        Processing
        Tesfaye Bekele collects cherries from 171 neighboring outgrowers. The cherries are pulped and fermented.
        This is our first Guji coffee! I love Ethiopian profiles that come out of Guji.
        """

    private func page(knownRoasters: [String] = []) -> BagDraft {
        BagLabel.details(
            of: BagLabel.Page(
                heading: "suke quto", title: "suke quto – delicate coffee roasters", site: "", text: sukeQuto,
                url: "https://delicate.coffee/products/suke-quto"),
            knownRoasters: knownRoasters, today: "2026-10-19")
    }

    @Test func readsAPageWithoutASiteName() {
        let draft = page()
        #expect(draft.coffee == "Suke Quto")
        #expect(draft.roaster == "Delicate Coffee Roasters")
        #expect(draft.country == "Ethiopia")
        #expect(draft.region == "Guji")
        #expect(draft.variety == "Kurume, Welicho")
        #expect(draft.process == "Washed")  // Not the paragraph under "Processing"
        #expect(draft.producer == "Tesfaye Bekele")
        #expect(draft.notes == "Yellow Peach, Bergamot, Dandelion")
        #expect(draft.weightGrams == nil)  // The sizes on sale aren't this bag's
        let stated: [BagField] = [.coffee, .roaster, .country, .region, .variety, .process, .producer, .notes, .url]
        #expect(stated.allSatisfy { !draft.isGuess($0) })
    }

    @Test func givesAKnownRoasterItsNameInTheApp() {
        #expect(page(knownRoasters: ["Onyx Coffee Lab", "Delicate"]).roaster == "Delicate")
    }

    @Test func findsTheSiteNameAtTheEndOfTheTitle() {
        #expect(BagLabel.siteName(inTitle: "suke quto – delicate coffee roasters", heading: "Suke Quto") == "delicate coffee roasters")
        #expect(BagLabel.siteName(inTitle: "Final Frontier | Proud Mary", heading: "Final Frontier") == "Proud Mary")
        #expect(BagLabel.siteName(inTitle: "Final Frontier", heading: "Final Frontier") == "")
    }
}

@Suite struct BagLabelTidyTests {
    @Test func putsALowercaseNameInTitleCase() {
        #expect(BagLabel.tidy("gachatha ab", name: true) == "Gachatha AB")
        #expect(BagLabel.tidy("golden raspberry") == "golden raspberry")  // Not a name: left as printed
    }

    @Test func putsCapitalsInTitleCase() {
        #expect(BagLabel.tidy("LUME COFFEE ROASTERS") == "Lume Coffee Roasters")
        #expect(BagLabel.tidy("H&S COFFEE ROASTERS") == "H&S Coffee Roasters")
        #expect(BagLabel.tidy("TIMOR-LESTE") == "Timor-Leste")
        #expect(BagLabel.tidy("SEY") == "Sey")
    }

    @Test func keepsCodesInCapitals() {
        #expect(BagLabel.tidy("GITITU AB") == "Gititu AB")
        #expect(BagLabel.tidy("PROUD MARY COFFEE USA") == "Proud Mary Coffee USA")
        #expect(BagLabel.tidy("SL28/34 WASHED") == "SL28/34 Washed")
    }

    @Test func leavesMixedCaseAlone() {
        #expect(BagLabel.tidy("Onyx Coffee LAB") == "Onyx Coffee LAB")
        #expect(BagLabel.tidy("golden raspberry") == "golden raspberry")
    }

    @Test func tidiesTheRoasterAndCoffeeReadFromALabel() {
        let reading = BagLabel.read(LabelPhotos.lume, knownRoasters: []).tidied
        #expect(reading.roaster == "Lume Coffee Roasters")
    }
}
