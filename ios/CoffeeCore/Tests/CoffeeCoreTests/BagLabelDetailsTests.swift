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

    @Test func takesTheCoffeesNameFromAShopsHeading() {
        // Headings from H&S, Lume, September and Proud Mary's pages
        let names = [
            "Ethiopia Habtamu Fekadu": "Habtamu Fekadu",
            "Burundi Mikuba 8": "Mikuba 8",
            "Danche 125g": "Danche",
            "Gititu AB 100g": "Gititu AB",
            "Juliana Guevara & Wbeimar Lasso | Java 100g": "Juliana Guevara & Wbeimar Lasso",
            "Dege Mullugeta - Ethiopia Anaerobic Natural": "Dege Mullugeta",
            "Sugar Dust - Colombia Geisha": "Sugar Dust",
            "Muchagara AB (Extra-light)": "Muchagara AB",
            "ETHIOPIA | Abana Estate | Anderacha | Heirloom | Washed": "Abana Estate Anderacha",
            "suke quto": "Suke Quto",
            "Kenya": "Kenya",
            // Shoebox, Datura, Thankfully and Love Letters put details in the name itself
            "Kenya Gachatha AB Washed(2026)": "Gachatha AB",
            "Ethiopia Ashenafi Getaneh Black Honey": "Ashenafi Getaneh",
            "Honduras Alexia Meija Parainema Washed": "Alexia Meija",
            "Elida Estate Plano Gesha Washed ASD DRD Lamastus Family": "Elida Estate Plano",
            "Kamoko Village SL28 - SL34 AA Fully Washed": "Kamoko Village",
            "Ecuador - Finca Soledad - Mejorado Wave Washed": "Finca Soledad",
            "Colombia - Gloria Cecilia - Chiroso (New Harvest)": "Gloria Cecilia",
            "Ayele Tulu - Bare Station - White Honey Process Landrace Ethiopia - 120g": "Ayele Tulu Bare Station",
            "Lady in Red": "Lady in Red",
            "La Fortuna": "La Fortuna",
        ]
        for (heading, name) in names {
            #expect(BagLabel.coffeeName(inHeading: heading) == name, "\(heading)")
        }
    }

    @Test func readsNotesUnderAHeadingAndMarksADescriptionAsAGuess() {
        let hAndS = BagLabel.labelled(
            ["Coffee flavor profile", "Danjou pear, gardenia, bergamot.", "Acidity: sparkling, lively"], today: "2026-10-19")
        #expect(hAndS.notes == "Danjou pear, gardenia, bergamot")
        #expect(!hAndS.isGuess(.notes))
        let september = BagLabel.labelled(
            [
                "In the cup",
                "We taste juicy and tart black currants, the acidity of grapefruit, and the sweetness of figs. This coffee has a silky body.",
            ],
            today: "2026-10-19")
        #expect(september.notes == "We taste juicy and tart black currants, the acidity of grapefruit, and the sweetness of figs")
        #expect(september.isGuess(.notes))
    }

    @Test func readsTheOriginsCountryAndRegion() {
        let shoebox = BagLabel.labelled(["Region: Aricha, Yirgacheffe, Ethiopia"], today: "2026-10-19")
        #expect([shoebox.country, shoebox.region] == ["Ethiopia", "Aricha, Yirgacheffe"])
        let datura = BagLabel.labelled(["Origin: Kenya - Nyeri County"], today: "2026-10-19")
        #expect([datura.country, datura.region] == ["Kenya", "Nyeri"])
        #expect(!datura.isGuess(.region))
    }

    @Test func takesOnlyTheNamesFromASentence() {
        // DAK's sections under each label, if its table weren't there first
        let dak = BagLabel.labelled(
            [
                "Origin", "Finca Zarza sits in the mountains of Bruselas, near Pitalito, Huila, at around 1750 to 1800 masl.",
                "Varietal", "Pacamara, a cross between Pacas and Maragogipe developed in El Salvador.",
                "Process", "The cherries ferment anaerobically for 72 hours submerged in water before being pulped.",
            ], today: "2026-10-19")
        #expect(dak.country == "")
        #expect(dak.region == "Huila")
        #expect(dak.variety == "Pacamara")
        #expect(dak.process == "")
        #expect(dak.isGuess(.region) && dak.isGuess(.variety))
    }

    @Test func cleansALabelledValue() {
        let shoebox = BagLabel.labelled(
            [
                "Varietal: Landrace(most varietals in Ethiopia are JARC selections like 74158 or 74112)",
                "Process: Washed: Fermented in open concrete tanks for 24-48 hours, then thoroughly washed.",
                "Tasting notes:", "Producer info and cup notes:",
            ], today: "2026-10-19")
        #expect(shoebox.variety == "Landrace")
        #expect(shoebox.process == "Washed")
        #expect(shoebox.notes == "")  // Not the next heading
        let loveLetters = BagLabel.labelled(["I taste:", "Potent floral boquet from ground aroma. Florals present."], today: "2026-10-19")
        #expect(loveLetters.notes == "Potent floral boquet from ground aroma")
    }

    @Test func readsTheHeadingAndSummaryForWhatsNotLabelled() {
        let draft = BagLabel.details(
            of: BagLabel.Page(
                heading: "Ethiopia - Chelbesa", title: "Chelbesa | Thankfully Coffee", site: "", text: "Region\nGedeb, Gedeo",
                url: "https://thankfullycoffee.com/products/chelbesa-g1",
                summary: "Chelbesa — Ethiopia, Gedeb, Gedeo. Tasting notes: Yellow Nectarine, Wildflower Honey, Orange Zest"),
            knownRoasters: [], today: "2026-10-19")
        #expect(draft.coffee == "Chelbesa")
        #expect(draft.roaster == "Thankfully Coffee")
        #expect(draft.country == "Ethiopia")
        #expect(draft.region == "Gedeb, Gedeo")
        #expect(draft.notes == "Yellow Nectarine, Wildflower Honey, Orange Zest")
        #expect(!draft.isGuess(.country) && !draft.isGuess(.notes))
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
