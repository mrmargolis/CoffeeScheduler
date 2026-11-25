import CoffeeCore
import Foundation

#if DEBUG
    /// A small, realistic database for screenshots and UI tests: one bag nearly
    /// finished, two resting, one in the freezer, one finished, and a weekend
    /// away. Debug builds only; launch with `-sample-data` to use it.
    enum SampleData {
        /// A Monday, so the schedule opens on a full week.
        static let today = "2026-10-12"

        static func store() throws -> CoffeeStore {
            let store = try CoffeeStore.inMemory()
            let db = store.db

            for bag in bags { try insert(bag, into: db) }

            try brews("brazil", from: "2026-10-02", to: "2026-10-06", rating: 3.5, into: db)
            try brews("guji", from: "2026-10-07", to: "2026-10-11", rating: 4.5, into: db)

            try dialIn(store)

            try event("huila", "freeze", "2026-09-12", into: db)
            try event("huila", "thaw", "2026-09-19", into: db)
            try event("gesha", "freeze", "2026-08-16", into: db)

            try db.run("INSERT INTO skip_days (start_date, end_date, reason) VALUES ('2026-10-16', '2026-10-18', 'Away')")
            try db.run("INSERT OR REPLACE INTO settings (key, value) VALUES ('last_import_date', '2026-10-11')")
            // Same as the global default, so the schedule is unchanged
            try db.run("INSERT INTO roaster_defaults (roaster, rest_days) VALUES ('Coffee Collective', 30)")
            try db.run(
                """
                INSERT INTO consumption_overrides (start_date, end_date, daily_grams, dose_size_grams)
                VALUES ('2026-10-14', '2026-10-14', 60, 20)
                """)
            return store
        }

        /// The Guji's dial-in: the first cup, the advisor's experiment after
        /// it (grind coarser), the second cup deciding it, and a change of
        /// the drinker's own left open for the next.
        private static func dialIn(_ store: CoffeeStore) throws {
            let first = evaluations[0]
            try store.saveEvaluation(first)
            let context = DialInContext(grinder: try store.grinderSetting("Femobook A4Z"))
            if let experiment = DialInAdvisor.advise([first], context: context).experiment {
                try store.saveExperiment(
                    SavedExperiment(
                        id: "sample-x1", beanID: "guji", createdFrom: first.id, createdAt: first.timestamp, start: first.recipe,
                        experiment: experiment))
            }
            let second = evaluations[1]
            try store.saveEvaluation(second)
            try store.decideOpenExperiment(with: second)
            try store.saveExperiment(
                SavedExperiment(
                    id: "sample-x2", beanID: "guji", createdFrom: second.id, createdAt: second.timestamp, start: second.recipe,
                    experiment: DialInExperiment.custom(DialInMove(.agitation, .down), to: "low", after: second, grinder: nil)))
        }

        /// Two cups of the Guji evaluated a day apart, the second a step coarser.
        static let evaluations: [CupEvaluation] = {
            let recipe = BrewRecipe(
                grinder: "Femobook A4Z", grindSetting: "1.6", temperatureC: 93, doseGrams: 15, waterGrams: 240, method: "Hario Alpha")
            var coarser = recipe
            coarser.grindSetting = "1.7"
            let day = { (date: String) in Double(DateUtils.dayNumber(date) ?? 0) * 86_400 + 25_200 }
            return [
                CupEvaluation(
                    id: "sample-1", beanID: "guji", timestamp: day("2026-10-10"), date: "2026-10-10",
                    recipe: CupRecipe(brew: recipe, agitation: .medium),
                    ratings: [.acidity: -1, .sweetness: -1, .clarity: -1, .finish: -2], drawdown: .slow,
                    character: [.muddy: .user], flavours: ["Blueberry"], notes: "Last pour drained very slowly. Short linger."),
                CupEvaluation(
                    id: "sample-2", beanID: "guji", timestamp: day("2026-10-11"), date: "2026-10-11",
                    recipe: CupRecipe(brew: coarser, agitation: .medium),
                    ratings: [.acidity: 0, .sweetness: 0, .clarity: 0, .body: 0, .finish: -1], drawdown: .normal, verdict: .better,
                    flavours: ["Blueberry", "Jasmine"]),
            ]
        }()

        private struct Bag {
            var id: String, name: String, roaster: String, roast: String
            var grams: Double = 250
            var country: String, region: String, variety: String, processing: String, flavour: String
            var archived = false
            var frozen = false
            var thaw: String?
            var freezeAfter: Double?
            var url: String?
        }

        private static let bags = [
            Bag(
                id: "brazil", name: "Daterra Sweet Collection", roaster: "Coffee Collective", roast: "2026-08-20",
                country: "Brazil", region: "Cerrado Mineiro", variety: "Mundo Novo", processing: "Pulped natural",
                flavour: "Milk chocolate, hazelnut", archived: true),
            Bag(
                id: "guji", name: "Guji Hambela", roaster: "Square Mile", roast: "2026-09-02",
                country: "Ethiopia", region: "Guji", variety: "Heirloom", processing: "Natural",
                flavour: "Blueberry, jasmine, cocoa nib", url: "www.squaremilecoffee.com/products/guji-hambela"),
            Bag(
                id: "huila", name: "La Esperanza", roaster: "Tim Wendelboe", roast: "2026-09-08",
                country: "Colombia", region: "Huila", variety: "Caturra", processing: "Washed",
                flavour: "Red apple, panela, orange zest"),
            Bag(
                id: "kenya", name: "Gichathaini AA", roaster: "Coffee Collective", roast: "2026-09-24",
                country: "Kenya", region: "Nyeri", variety: "SL28, SL34", processing: "Washed",
                flavour: "Blackcurrant, grapefruit, tomato leaf", freezeAfter: 125),
            Bag(
                id: "gesha", name: "Janson Gesha", roaster: "Onyx", roast: "2026-08-12", grams: 100,
                country: "Panama", region: "Volcán", variety: "Gesha", processing: "Washed",
                flavour: "Bergamot, peach, honeysuckle", frozen: true, thaw: "2026-10-27"),
        ]

        private static func insert(_ bag: Bag, into db: SQLiteDatabase) throws {
            try db.run(
                """
                INSERT INTO beans (id, name, roaster, roast_date, weight_grams, country, region, variety,
                  processing, flavour_profile, archived, is_frozen, planned_thaw_date, freeze_after_grams, url)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(bag.id), .text(bag.name), .text(bag.roaster), .text(bag.roast), .double(bag.grams),
                    .text(bag.country), .text(bag.region), .text(bag.variety), .text(bag.processing), .text(bag.flavour),
                    SQLValue(bag.archived), SQLValue(bag.frozen), SQLValue(bag.thaw), SQLValue(bag.freezeAfter),
                    SQLValue(bag.url),
                ])
        }

        /// Three 15 g brews a day across the given dates, each with a recipe,
        /// and a rating on the first.
        private static func brews(
            _ beanID: String, from start: String, to end: String, rating: Double, into db: SQLiteDatabase
        ) throws {
            for (i, date) in DateUtils.dateRange(start, end).enumerated() {
                for cup in 0..<3 {
                    try db.run(
                        """
                        INSERT INTO brews (bean_id, ground_coffee_grams, creation_date, rating, logged_at,
                          grinder, grind_setting, temperature_c, water_grams, brew_seconds, method)
                        VALUES (?, 15, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        [
                            .text(beanID), .text(date), cup == 0 ? .double(rating - Double(i % 2) * 0.5) : .null,
                            .double(Double(DateUtils.dayNumber(date) ?? 0) * 86_400 + 25_200 + Double(cup) * 1_800),
                            "Femobook A4Z", .text(i % 2 == 0 ? "1.6" : "1.7"), 93, 240, 208, "Hario Alpha",
                        ]
                    )
                }
            }
        }

        private static func event(_ beanID: String, _ kind: String, _ date: String, into db: SQLiteDatabase) throws {
            try db.run(
                "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, ?, ?)",
                [.text(beanID), .text(kind), .text(date)]
            )
        }
    }
#endif
