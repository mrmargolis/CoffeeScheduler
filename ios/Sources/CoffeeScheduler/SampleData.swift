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

        func bean(
            _ id: String, _ name: String, _ roaster: String, roast: String, grams: Double = 250,
            country: String?, region: String?, variety: String?, processing: String?, flavour: String?,
            archived: Bool = false, frozen: Bool = false, thaw: String? = nil, freezeAfter: Double? = nil
        ) throws {
            try db.run("""
                INSERT INTO beans (id, name, roaster, roast_date, weight_grams, country, region, variety,
                  processing, flavour_profile, archived, is_frozen, planned_thaw_date, freeze_after_grams)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [
                    .text(id), .text(name), .text(roaster), .text(roast), .double(grams),
                    SQLValue(country), SQLValue(region), SQLValue(variety), SQLValue(processing), SQLValue(flavour),
                    SQLValue(archived), SQLValue(frozen), SQLValue(thaw), SQLValue(freezeAfter),
                ])
        }

        /// Three 15 g brews a day across the given dates, with a rating on the first.
        func brews(_ beanID: String, from start: String, to end: String, rating: Double) throws {
            for (i, date) in DateUtils.dateRange(start, end).enumerated() {
                for cup in 0..<3 {
                    try db.run(
                        "INSERT INTO brews (bean_id, ground_coffee_grams, creation_date, rating) VALUES (?, 15, ?, ?)",
                        [.text(beanID), .text(date), cup == 0 ? .double(rating - Double(i % 2) * 0.5) : .null]
                    )
                }
            }
        }

        func event(_ beanID: String, _ kind: String, _ date: String) throws {
            try db.run(
                "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, ?, ?)",
                [.text(beanID), .text(kind), .text(date)]
            )
        }

        try bean("brazil", "Daterra Sweet Collection", "Coffee Collective", roast: "2026-08-20",
                 country: "Brazil", region: "Cerrado Mineiro", variety: "Mundo Novo", processing: "Pulped natural",
                 flavour: "Milk chocolate, hazelnut", archived: true)
        try bean("guji", "Guji Hambela", "Square Mile", roast: "2026-09-02",
                 country: "Ethiopia", region: "Guji", variety: "Heirloom", processing: "Natural",
                 flavour: "Blueberry, jasmine, cocoa nib")
        try bean("huila", "La Esperanza", "Tim Wendelboe", roast: "2026-09-08",
                 country: "Colombia", region: "Huila", variety: "Caturra", processing: "Washed",
                 flavour: "Red apple, panela, orange zest")
        try bean("kenya", "Gichathaini AA", "Coffee Collective", roast: "2026-09-24",
                 country: "Kenya", region: "Nyeri", variety: "SL28, SL34", processing: "Washed",
                 flavour: "Blackcurrant, grapefruit, tomato leaf", freezeAfter: 125)
        try bean("gesha", "Janson Gesha", "Onyx", roast: "2026-08-12", grams: 100,
                 country: "Panama", region: "Volcán", variety: "Gesha", processing: "Washed",
                 flavour: "Bergamot, peach, honeysuckle", frozen: true, thaw: "2026-10-27")

        try brews("brazil", from: "2026-10-02", to: "2026-10-06", rating: 3.5)
        try brews("guji", from: "2026-10-07", to: "2026-10-11", rating: 4.5)

        try event("huila", "freeze", "2026-09-12")
        try event("huila", "thaw", "2026-09-19")
        try event("gesha", "freeze", "2026-08-16")

        try db.run("INSERT INTO skip_days (start_date, end_date, reason) VALUES ('2026-10-16', '2026-10-18', 'Away')")
        // Same as the global default, so the schedule is unchanged
        try db.run("INSERT INTO roaster_defaults (roaster, rest_days) VALUES ('Coffee Collective', 30)")
        try db.run(
            "INSERT INTO consumption_overrides (start_date, end_date, daily_grams, dose_size_grams) VALUES ('2026-10-14', '2026-10-14', 60, 20)"
        )
        return store
    }
}
#endif
