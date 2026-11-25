import Foundation

extension CoffeeStore {
    /// The recipe of the bag's latest brew; nil when it has no brews or the
    /// latest one recorded nothing about how it was brewed.
    public func latestBrewRecipe(beanID: String) throws -> BrewRecipe? {
        guard
            let row = try db.query(
                "SELECT * FROM brews WHERE bean_id = ? ORDER BY creation_date DESC, logged_at DESC, id DESC LIMIT 1",
                [.text(beanID)]
            ).first
        else { return nil }
        let recipe = BrewRecipe(
            grinder: row.string("grinder"),
            grindSetting: row.string("grind_setting"),
            temperatureC: row.double("temperature_c"),
            doseGrams: row.double("ground_coffee_grams").flatMap { $0 > 0 ? $0 : nil },
            waterGrams: row.double("water_grams"),
            brewSeconds: row.int("brew_seconds"),
            method: row.string("method"),
            water: row.string("water"),
            profile: row.string("profile")
        )
        return recipe.isEmpty ? nil : recipe
    }
}
