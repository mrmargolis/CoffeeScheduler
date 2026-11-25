import Foundation
import Testing

@testable import CoffeeCore

/// An export whose brew names a grinder, method and water by ID, as
/// BeanConqueror's does.
private func recipeExport(brews: [[String: Any]]) throws -> Data {
    try makeZip([
        "Beanconqueror.json": [
            "BEANS": [bcBean()],
            "BREWS": brews,
            "MILL": [["name": "Femobook A4Z", "config": ["uuid": "mill-1"]]],
            "PREPARATION": [["name": "Hario Alpha", "config": ["uuid": "prep-1"]]],
            "WATER": [["name": "Barista Tears", "config": ["uuid": "water-1"]]],
        ]
    ])
}

private func fullBrew(_ overrides: [String: Any] = [:]) -> [String: Any] {
    bcBrew(
        [
            "mill": "mill-1", "grind_size": 1.6, "brew_temperature": 93, "brew_quantity": 240, "brew_time": 208,
            "method_of_preparation": "prep-1", "water": "water-1", "pressure_profile": "Four Pour",
            "note": "  50/130/200/240\nStone fruit mostly.\n",
        ].merging(overrides) { _, new in new })
}

private func parseBrew(_ overrides: [String: Any] = [:]) throws -> BeanConquerorParser.RawBrew {
    try #require(BeanConquerorParser.parse(zipData: try recipeExport(brews: [fullBrew(overrides)]), timeZone: utc).brews.first)
}

@Suite struct BrewRecipeParsingTests {
    @Test func readsTheWholeRecipeWithNamesResolved() throws {
        let brew = try parseBrew()
        #expect(brew.brewID == "brew-1")
        #expect(brew.timestamp == 1_706_788_800)
        #expect(brew.notes == "50/130/200/240\nStone fruit mostly.")
        #expect(
            brew.recipe
                == BrewRecipe(
                    grinder: "Femobook A4Z", grindSetting: "1.6", temperatureC: 93, doseGrams: 15, waterGrams: 240,
                    brewSeconds: 208, method: "Hario Alpha", water: "Barista Tears", profile: "Four Pour"
                ))
    }

    @Test(arguments: [
        (93.0, 93.0 as Double?), (100, 100), (100.5, 100.5), (101, 38.3), (203, 95), (212, 100), (0, nil), (-4, nil),
    ])
    func temperatureBelow101IsCelsiusAndAboveIsFahrenheit(exported: Double, celsius: Double?) throws {
        #expect(try parseBrew(["brew_temperature": exported]).recipe.temperatureC == celsius)
    }

    @Test func grindSettingFromANumberOrAString() throws {
        #expect(try parseBrew(["grind_size": 4]).recipe.grindSetting == "4")
        #expect(try parseBrew(["grind_size": 4.4]).recipe.grindSetting == "4.4")
        #expect(try parseBrew(["grind_size": " 6.1 "]).recipe.grindSetting == "6.1")
        #expect(try parseBrew(["grind_size": "6.1"]).recipe.grindValue == 6.1)
        #expect(try parseBrew(["grind_size": "click 12"]).recipe.grindValue == nil)
    }

    @Test func zerosAndBlanksAreUnknown() throws {
        let brew = try parseBrew([
            "grind_size": 0, "brew_temperature": 0, "brew_quantity": 0, "brew_time": 0, "grind_weight": 0,
            "pressure_profile": "", "note": "  \n", "mill": "", "method_of_preparation": "missing",
        ])
        #expect(brew.recipe == BrewRecipe(water: "Barista Tears"))
        #expect(brew.notes == nil)
    }

    @Test func ratingsBelowOneAreUnknownButTheTopOfTheScaleIsKept() throws {
        #expect(try parseBrew(["rating": 0]).rating == nil)
        #expect(try parseBrew(["rating": -1]).rating == nil)
        #expect(try parseBrew(["rating": 1]).rating == 1)
        // BeanConqueror's scale can run past 5
        #expect(try parseBrew(["rating": 6]).rating == 6)
    }
}

@Suite struct BrewRecipeStoreTests {
    @Test func latestRecipeComesFromTheNewestBrew() throws {
        let store = try CoffeeStore.inMemory()
        let earlier = fullBrew(["grind_size": 1.5, "config": ["uuid": "brew-0", "unix_timestamp": 1_706_785_200]])
        let later = fullBrew(["grind_size": 1.7, "config": ["uuid": "brew-2", "unix_timestamp": 1_706_790_000]])
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try recipeExport(brews: [later, earlier, fullBrew()]), timeZone: utc))

        let recipe = try #require(try store.latestBrewRecipe(beanID: "uuid-1"))
        #expect(recipe.grindSetting == "1.7")
        #expect(recipe.method == "Hario Alpha")
        #expect(recipe.ratio == 16)
    }

    @Test func noRecipeWithoutBrewsOrWithNothingRecorded() throws {
        let store = try CoffeeStore.inMemory()
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()]), timeZone: utc))
        #expect(try store.latestBrewRecipe(beanID: "uuid-1") == nil)

        _ = try store.importExport(
            BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()], brews: [bcBrew(["grind_weight": 0])]), timeZone: utc))
        #expect(try store.latestBrewRecipe(beanID: "uuid-1") == nil)
    }

    @Test func reimportReplacesBrewsAndKeepsTheirBeanConquerorIDs() throws {
        let store = try CoffeeStore.inMemory()
        let parsed = BeanConquerorParser.parse(zipData: try recipeExport(brews: [fullBrew()]), timeZone: utc)
        _ = try store.importExport(parsed)
        _ = try store.importExport(parsed)

        let rows = try store.db.query("SELECT bc_uuid, logged_at, notes FROM brews")
        #expect(rows.count == 1)
        #expect(rows.first?.string("bc_uuid") == "brew-1")
        #expect(rows.first?.double("logged_at") == 1_706_788_800)
        #expect(rows.first?.string("notes") == "50/130/200/240\nStone fruit mostly.")
    }

    @Test func aVersionOneDatabaseGainsTheRecipeColumnsAndKeepsItsData() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.execute(
            """
            CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            INSERT INTO settings (key, value) VALUES ('daily_consumption_grams', '30');
            CREATE TABLE beans (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, roaster TEXT NOT NULL DEFAULT '', roast_date TEXT,
              weight_grams REAL NOT NULL DEFAULT 0, cost REAL, flavour_profile TEXT, country TEXT, region TEXT,
              variety TEXT, processing TEXT, archived INTEGER NOT NULL DEFAULT 0, rest_days INTEGER,
              is_frozen INTEGER NOT NULL DEFAULT 0, notes TEXT, display_order INTEGER,
              planned_thaw_date TEXT, freeze_after_grams REAL, url TEXT
            );
            CREATE TABLE brews (
              id INTEGER PRIMARY KEY AUTOINCREMENT, bean_id TEXT NOT NULL REFERENCES beans(id),
              ground_coffee_grams REAL NOT NULL DEFAULT 0, creation_date TEXT NOT NULL, bean_age_days INTEGER, rating REAL
            );
            INSERT INTO beans (id, name, weight_grams) VALUES ('old', 'Old Bean', 250);
            INSERT INTO brews (bean_id, ground_coffee_grams, creation_date, rating) VALUES ('old', 15, '2026-01-20', 4);
            PRAGMA user_version = 1;
            """)

        let store = try CoffeeStore(db: db)

        #expect(try db.query("PRAGMA user_version").first?.int("user_version") == 2)
        #expect(try store.bean(id: "old")?.name == "Old Bean")
        #expect(try store.recentBrews(beanID: "old").map(\.rating) == [4])
        #expect(try db.query("SELECT value FROM settings WHERE key = 'daily_consumption_grams'").first?.string("value") == "30")
        #expect(try store.latestBrewRecipe(beanID: "old") == BrewRecipe(doseGrams: 15))
    }
}

@Suite struct BrewRecipeSummaryTests {
    @Test func summaryNamesWhatIsKnown() {
        let recipe = BrewRecipe(
            grinder: "A4Z", grindSetting: "1.6", temperatureC: 93, doseGrams: 15, waterGrams: 240, brewSeconds: 208,
            method: "Hario Alpha", water: "Barista Tears", profile: "Four Pour")
        #expect(
            recipe.summaryParts == ["A4Z 1.6", "93 °C", "15 g : 240 g (1:16)", "3:28", "Hario Alpha", "Barista Tears", "Four Pour"])
    }

    @Test func summaryLeavesOutWhatIsUnknown() {
        #expect(BrewRecipe(grindSetting: "4.4", doseGrams: 15).summaryParts == ["4.4", "15 g"])
        #expect(BrewRecipe(temperatureC: 95.04, doseGrams: 15, waterGrams: 255.7).summaryParts == ["95 °C", "15 g : 255.7 g (1:17)"])
        #expect(BrewRecipe().summaryParts.isEmpty)
    }
}
