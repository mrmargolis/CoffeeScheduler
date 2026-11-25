import Foundation
import Testing

@testable import CoffeeCore

/// 2024-02-01 12:00 UTC.
private let noon: Double = 1_706_788_800
private let minute: Double = 60

/// A brew of `bean` logged `minutes` after noon.
private func brew(_ id: String, at minutes: Double, bean: String = "uuid-1", grind: Double = 1.6) -> [String: Any] {
    bcBrew([
        "bean": bean, "config": ["uuid": id, "unix_timestamp": noon + minutes * minute], "grind_size": grind,
        "brew_temperature": 93, "brew_quantity": 240,
    ])
}

/// A cup of uuid-1 evaluated `minutes` after noon.
private func cup(_ id: String, at minutes: Double, grind: String = "1.6") -> CupEvaluation {
    CupEvaluation(
        id: id, beanID: "uuid-1", timestamp: noon + minutes * minute, date: "2024-02-01",
        recipe: CupRecipe(brew: BrewRecipe(grindSetting: grind, temperatureC: 93, doseGrams: 15, waterGrams: 240)))
}

private func importing(_ brews: [[String: Any]], into store: CoffeeStore) throws {
    let beans = [bcBean(), bcBean(["name": "Other", "config": ["uuid": "uuid-2", "unix_timestamp": 1_700_000_000]])]
    _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: beans, brews: brews), timeZone: utc))
}

/// Each evaluation's brew, by evaluation ID.
private func links(_ store: CoffeeStore) throws -> [String: String] {
    try store.evaluations(beanID: "uuid-1").reduce(into: [:]) { $0[$1.id] = $1.brewID }
}

@Suite struct BrewLinkTests {
    private let store: CoffeeStore

    init() throws {
        store = try CoffeeStore.inMemory()
        try importing([], into: store)
    }

    @Test func linksTheBrewBeforeNotTheNearest() throws {
        try store.saveEvaluation(cup("e1", at: 15))
        try importing([brew("b1", at: 0), brew("b2", at: 20)], into: store)
        #expect(try links(store) == ["e1": "b1"])
    }

    @Test func notBeyondThreeHours() throws {
        try store.saveEvaluation(cup("e1", at: 181))
        try importing([brew("b1", at: 0)], into: store)
        #expect(try links(store).isEmpty)
    }

    @Test func otherBagsAreIgnored() throws {
        try store.saveEvaluation(cup("e1", at: 15))
        try importing([brew("b1", at: 0), brew("other", at: 10, bean: "uuid-2")], into: store)
        #expect(try links(store) == ["e1": "b1"])
    }

    @Test func cupsInOneSittingPairWithItsBrewsInOrder() throws {
        // Brewed at 0 and 20, both evaluated after the second brew
        try store.saveEvaluation(cup("e1", at: 25))
        try store.saveEvaluation(cup("e2", at: 30))
        try importing([brew("b1", at: 0), brew("b2", at: 20)], into: store)
        #expect(try links(store) == ["e1": "b1", "e2": "b2"])
    }

    @Test func aCupSavedAfterTheImportLinksStraightAway() throws {
        try importing([brew("b1", at: 0)], into: store)
        try store.saveEvaluation(cup("e1", at: 10))
        #expect(try links(store) == ["e1": "b1"])
    }

    @Test func autoLinksAreWorkedOutAgainOnReimport() throws {
        try store.saveEvaluation(cup("e1", at: 30))
        try importing([brew("b1", at: 0)], into: store)
        try importing([brew("b1", at: 0), brew("b2", at: 25)], into: store)
        #expect(try links(store) == ["e1": "b2"])
    }

    @Test func aLinkByHandSurvivesReimport() throws {
        try store.saveEvaluation(cup("e1", at: 30))
        try importing([brew("b1", at: 0), brew("b2", at: 25)], into: store)
        var linked = try #require(try store.evaluations(beanID: "uuid-1").first)
        linked.brewID = "b1"
        linked.linkedByHand = true
        try store.saveEvaluation(linked)
        try importing([brew("b1", at: 0), brew("b2", at: 25)], into: store)
        #expect(try links(store) == ["e1": "b1"])
    }

    @Test func unlinkedByHandStaysUnlinked() throws {
        var unlinked = cup("e1", at: 10)
        unlinked.linkedByHand = true
        try store.saveEvaluation(unlinked)
        try importing([brew("b1", at: 0)], into: store)
        #expect(try links(store).isEmpty)
    }

    @Test func aVanishedBrewClearsALinkByHand() throws {
        var linked = cup("e1", at: 200)
        linked.brewID = "b1"
        linked.linkedByHand = true
        try importing([brew("b1", at: 0)], into: store)
        try store.saveEvaluation(linked)
        try importing([brew("b2", at: 5)], into: store)
        let saved = try #require(try store.evaluations(beanID: "uuid-1").first)
        #expect(saved.brewID == nil)
        #expect(saved.linkedByHand == false)
    }

    @Test func aBrewLinkedByHandIsTakenFromAnotherCup() throws {
        try store.saveEvaluation(cup("e1", at: 10))
        try store.saveEvaluation(cup("e2", at: 60))
        try importing([brew("b1", at: 0), brew("b2", at: 50)], into: store)
        var second = try #require(try store.evaluations(beanID: "uuid-1").first { $0.id == "e2" })
        second.brewID = "b1"
        second.linkedByHand = true
        try store.saveEvaluation(second)
        // e1 goes to the next brew back it can have: none
        #expect(try links(store) == ["e2": "b1"])
    }

    @Test func deletingACupFreesItsBrew() throws {
        try store.saveEvaluation(cup("e1", at: 25))
        try store.saveEvaluation(cup("e2", at: 30))
        try importing([brew("b1", at: 0), brew("b2", at: 20)], into: store)
        try store.deleteEvaluation(id: "e2")
        #expect(try links(store) == ["e1": "b2"])
    }

    @Test func recentNotesAreTheNewestBrewsWithNotesFromAnyBag() throws {
        var noted = brew("b2", at: 10)
        noted["note"] = "Sour. Try finer."
        var other = brew("o1", at: 20, bean: "uuid-2")
        other["note"] = "Peach"
        var blank = brew("b3", at: 30)
        blank["note"] = "  "
        try importing([brew("b1", at: 0), noted, other, blank], into: store)
        #expect(try store.recentBrewNotes(limit: 5).map(\.id) == ["o1", "b2"])
        #expect(try store.recentBrewNotes(limit: 1).map(\.notes) == ["Peach"])
    }

    @Test func brewsNearACupNewestFirst() throws {
        try importing([brew("b1", at: -13 * 60), brew("b2", at: 0), brew("b3", at: 20)], into: store)
        #expect(try store.brews(near: cup("e1", at: 10)).map(\.id) == ["b3", "b2"])
    }
}

@Suite struct BrewLinkSchemaTests {
    @Test func aVersionTwoFileWithoutTheLinkColumnsGainsThem() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        _ = try CoffeeStore(db: db)
        try db.execute(
            "ALTER TABLE cup_evaluations DROP COLUMN brew_linked_by_hand; ALTER TABLE cup_evaluations DROP COLUMN brew_uuid")

        let store = try CoffeeStore(db: db)
        try importing([brew("b1", at: 0)], into: store)
        try store.saveEvaluation(cup("e1", at: 10))
        #expect(try links(store) == ["e1": "b1"])
    }
}

@Suite struct ImportedRecipeTests {
    private let typed = BrewRecipe(
        grinder: "A4Z", grindSetting: "1.6", temperatureC: 93, doseGrams: 15, waterGrams: 240, method: "V60")

    @Test func onlyDifferingFieldsAreListed() {
        var imported = typed
        imported.grindSetting = "1.7"
        imported.temperatureC = 94
        imported.method = nil  // not recorded, so not a difference
        imported.brewSeconds = 180  // not kept with an evaluation
        #expect(
            typed.differences(from: imported) == [
                RecipeDifference(field: "Grind", typed: "1.6", imported: "1.7"),
                RecipeDifference(field: "Temperature", typed: "93 °C", imported: "94 °C"),
            ])
    }

    @Test func theSameGrindWrittenDifferentlyIsntADifference() {
        var imported = typed
        imported.grindSetting = "1.60"
        #expect(typed.differences(from: imported).isEmpty)
    }

    @Test func aFieldNotTypedIsADifference() {
        var blank = typed
        blank.profile = nil
        var imported = typed
        imported.profile = "Four Pour"
        #expect(blank.differences(from: imported) == [RecipeDifference(field: "Profile", typed: nil, imported: "Four Pour")])
    }

    @Test func usingImportedTakesWhatTheBrewRecorded() {
        let imported = BrewRecipe(grindSetting: "1.7", temperatureC: 94, profile: "Four Pour")
        #expect(
            typed.usingImported(imported)
                == BrewRecipe(
                    grinder: "A4Z", grindSetting: "1.7", temperatureC: 94, doseGrams: 15, waterGrams: 240, method: "V60",
                    profile: "Four Pour"))
    }

    @Test func usingImportedLeavesDecidedExperimentsAlone() throws {
        let store = try CoffeeStore.inMemory()
        try importing([brew("b1", at: 0, grind: 1.8)], into: store)
        let first = cup("e0", at: -60)
        let experiment = SavedExperiment(
            beanID: "uuid-1", createdFrom: "e0", createdAt: first.timestamp, start: first.recipe,
            experiment: DialInExperiment(
                move: DialInMove(.grind, .down), from: "1.6", to: "1.7", toValue: 1.7, targets: [.finish: -2], targetTags: [],
                numberDirection: 1, expectedEffect: "", criteria: []))
        try store.saveExperiment(experiment)
        var next = cup("e1", at: 10, grind: "1.7")
        next.ratings = [.finish: -1]
        _ = try store.decideOpenExperiment(with: next)
        try store.saveEvaluation(next)
        let before = try store.experiments(beanID: "uuid-1")

        var edited = try #require(try store.evaluations(beanID: "uuid-1").first { $0.id == "e1" })
        let imported = try #require(try store.linkedBrew(for: edited))
        edited.recipe.brew = edited.recipe.brew.usingImported(imported.recipe)
        try store.saveEvaluation(edited)

        #expect(try store.evaluations(beanID: "uuid-1").first { $0.id == "e1" }?.recipe.brew.grindSetting == "1.8")
        #expect(try store.experiments(beanID: "uuid-1") == before)
        #expect(before.first?.outcome == .improved)
    }
}
