import Foundation
import Testing

@testable import CoffeeCore

/// A store with brews on `grinder` at each of `settings`, in order, for bag uuid-1.
private func store(grinder: String = "Femobook A4Z", settings: [Any]) throws -> CoffeeStore {
    let brews = settings.enumerated().map { i, setting in
        bcBrew([
            "mill": "mill-1", "grind_size": setting, "config": ["uuid": "brew-\(i)", "unix_timestamp": 1_706_788_800 + i * 3_600],
        ])
    }
    let zip = try makeZip([
        "Beanconqueror.json": ["BEANS": [bcBean()], "BREWS": brews, "MILL": [["name": grinder, "config": ["uuid": "mill-1"]]]]
    ])
    let store = try CoffeeStore.inMemory()
    _ = try store.importExport(BeanConquerorParser.parse(zipData: zip, timeZone: utc))
    return store
}

@Suite struct GrinderHistoryTests {
    @Test func usualStepIsTheMostCommonChange() {
        let history = GrinderHistory(runs: [[1.6, 1.7, 1.8, 1.75, 1.7], [1.5, 1.6]])
        #expect(history.usualStep == 0.1)
    }

    @Test func aTieGoesToTheSmallerStep() {
        #expect(GrinderHistory(runs: [[1.6, 1.65, 1.75, 1.8, 1.9]]).usualStep == 0.05)
    }

    @Test func changesBetweenBagsDontCount() {
        // 4 → 8 is a new bag, not a step
        #expect(GrinderHistory(runs: [[4, 5, 6], [8, 9]]).usualStep == 1)
    }

    @Test func tooFewChangesGiveNoStep() {
        #expect(GrinderHistory(runs: [[1.6, 1.7, 1.7]]).usualStep == nil)
    }

    @Test func usualRangeIsTheMiddleNinetyPercent() {
        // 20 settings 1...20, plus nothing else: 5th is 1, 95th is 19
        let history = GrinderHistory(runs: [(1...20).map(Double.init)])
        #expect(history.usualRange == 1...19)
        #expect(history.isUnusual(20))
        #expect(!history.isUnusual(10))
    }

    @Test func aFewSettingsOnAnotherScaleAreUnusual() {
        // Mostly under 20, with a few on the other scale, as on a Timemore 078
        let history = GrinderHistory(runs: [Array(repeating: 8.0, count: 30) + [9, 10, 7, 54]])
        #expect(history.isUnusual(54))
        #expect(!history.isUnusual(8))
    }

    @Test func tooLittleHistoryHasNoRange() {
        let history = GrinderHistory(runs: [[1, 2, 3]])
        #expect(history.usualRange == nil)
        #expect(!history.isUnusual(99))
    }
}

@Suite struct GrinderSettingStoreTests {
    @Test func grindersComeFromImportsWithLearnedDefaults() throws {
        let store = try store(settings: [1.6, 1.7, 1.8, 1.7, 1.6, 1.65, 1.6, 1.7, 1.8, 1.9, "1.7"])
        let grinder = try #require(try store.grinderSettings().first)
        #expect(grinder.name == "Femobook A4Z")
        #expect(grinder.effectiveStep == 0.1)
        #expect(grinder.higherIsCoarser)
        #expect(grinder.step == nil)
    }

    @Test func editedValuesWinAndSurviveAReimport() throws {
        let store = try store(settings: [1.6, 1.7, 1.8, 1.9])
        try store.setGrinder("Femobook A4Z", step: 0.05, higherIsCoarser: false)
        let again = try store.db.query("SELECT COUNT(*) AS n FROM brews").first?.int("n")
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()], brews: [bcBrew()]), timeZone: utc))
        #expect(again == 4)

        // The grinder's brews are gone, but its settings wait for it
        #expect(try store.grinderSetting("Femobook A4Z") == nil)
        #expect(try store.db.query("SELECT step, higher_is_coarser FROM grinder_settings").first?.double("step") == 0.05)
    }

    @Test func editedValuesWinOverTheLearnedOnes() throws {
        let store = try store(settings: [1.6, 1.7, 1.8, 1.9])
        try store.setGrinder("Femobook A4Z", step: 0.05, higherIsCoarser: false)
        let grinder = try #require(try store.grinderSetting("Femobook A4Z"))
        #expect(grinder.effectiveStep == 0.05)
        #expect(grinder.higherIsCoarser == false)
    }

    @Test func clearingTheStepGoesBackToTheLearnedOne() throws {
        let store = try store(settings: [1.6, 1.7, 1.8, 1.9])
        try store.setGrinder("Femobook A4Z", step: 0.05, higherIsCoarser: true)
        try store.setGrinder("Femobook A4Z", step: nil, higherIsCoarser: true)
        #expect(try store.grinderSetting("Femobook A4Z")?.effectiveStep == 0.1)
    }

    @Test func temperatureStepDefaultsToTwoDegrees() throws {
        let store = try CoffeeStore.inMemory()
        #expect(try store.temperatureStep() == 2)
        try store.setTemperatureStep(1)
        #expect(try store.temperatureStep() == 1)
    }
}
