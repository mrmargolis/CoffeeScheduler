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

        try event("huila", "freeze", "2026-09-12", into: db)
        try event("huila", "thaw", "2026-09-19", into: db)
        try event("gesha", "freeze", "2026-08-16", into: db)

        try db.run("INSERT INTO skip_days (start_date, end_date, reason) VALUES ('2026-10-16', '2026-10-18', 'Away')")
        // Same as the global default, so the schedule is unchanged
        try db.run("INSERT INTO roaster_defaults (roaster, rest_days) VALUES ('Coffee Collective', 30)")
        try db.run("""
            INSERT INTO consumption_overrides (start_date, end_date, daily_grams, dose_size_grams)
            VALUES ('2026-10-14', '2026-10-14', 60, 20)
            """)
        return store
    }

    private struct Bag {
        var id: String, name: String, roaster: String, roast: String
        var grams: Double = 250
        var country: String, region: String, variety: String, processing: String, flavour: String
        var archived = false
        var frozen = false
        var thaw: String?
        var freezeAfter: Double?
    }

    private static let bags = [
        Bag(id: "brazil", name: "Daterra Sweet Collection", roaster: "Coffee Collective", roast: "2026-08-20",
            country: "Brazil", region: "Cerrado Mineiro", variety: "Mundo Novo", processing: "Pulped natural",
            flavour: "Milk chocolate, hazelnut", archived: true),
        Bag(id: "guji", name: "Guji Hambela", roaster: "Square Mile", roast: "2026-09-02",
            country: "Ethiopia", region: "Guji", variety: "Heirloom", processing: "Natural",
            flavour: "Blueberry, jasmine, cocoa nib"),
        Bag(id: "huila", name: "La Esperanza", roaster: "Tim Wendelboe", roast: "2026-09-08",
            country: "Colombia", region: "Huila", variety: "Caturra", processing: "Washed",
            flavour: "Red apple, panela, orange zest"),
        Bag(id: "kenya", name: "Gichathaini AA", roaster: "Coffee Collective", roast: "2026-09-24",
            country: "Kenya", region: "Nyeri", variety: "SL28, SL34", processing: "Washed",
            flavour: "Blackcurrant, grapefruit, tomato leaf", freezeAfter: 125),
        Bag(id: "gesha", name: "Janson Gesha", roaster: "Onyx", roast: "2026-08-12", grams: 100,
            country: "Panama", region: "Volcán", variety: "Gesha", processing: "Washed",
            flavour: "Bergamot, peach, honeysuckle", frozen: true, thaw: "2026-10-27"),
    ]

    private static func insert(_ bag: Bag, into db: SQLiteDatabase) throws {
        try db.run("""
            INSERT INTO beans (id, name, roaster, roast_date, weight_grams, country, region, variety,
              processing, flavour_profile, archived, is_frozen, planned_thaw_date, freeze_after_grams)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                .text(bag.id), .text(bag.name), .text(bag.roaster), .text(bag.roast), .double(bag.grams),
                .text(bag.country), .text(bag.region), .text(bag.variety), .text(bag.processing), .text(bag.flavour),
                SQLValue(bag.archived), SQLValue(bag.frozen), SQLValue(bag.thaw), SQLValue(bag.freezeAfter),
            ])
    }

    /// Three 15 g brews a day across the given dates, with a rating on the first.
    private static func brews(
        _ beanID: String, from start: String, to end: String, rating: Double, into db: SQLiteDatabase
    ) throws {
        for (i, date) in DateUtils.dateRange(start, end).enumerated() {
            for cup in 0..<3 {
                try db.run(
                    "INSERT INTO brews (bean_id, ground_coffee_grams, creation_date, rating) VALUES (?, 15, ?, ?)",
                    [.text(beanID), .text(date), cup == 0 ? .double(rating - Double(i % 2) * 0.5) : .null]
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
