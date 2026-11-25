import Foundation

/// A brew from the BeanConqueror import, as an evaluation links to it.
public struct LoggedBrew: Hashable, Sendable, Identifiable {
    /// BeanConqueror's ID for the brew.
    public var id: String
    public var beanID: String
    /// When it was logged, in seconds since 1970.
    public var timestamp: Double
    public var recipe: BrewRecipe
    public var rating: Double?
    public var notes: String?

    public init(
        id: String, beanID: String, timestamp: Double, recipe: BrewRecipe = BrewRecipe(), rating: Double? = nil, notes: String? = nil
    ) {
        self.id = id
        self.beanID = beanID
        self.timestamp = timestamp
        self.recipe = recipe
        self.rating = rating
        self.notes = notes
    }
}

/// Which brew each evaluation describes.
public enum BrewLinker {
    /// How long after a brew an evaluation of it can be.
    public static let window: Double = 3 * 3600

    /// The brew of each evaluation not linked by hand, by evaluation ID; one
    /// with no brew is left out. Each goes to the latest brew of its bag at
    /// or before it, within `window`, that no other cup has: not the
    /// closest brew, since a bag is often brewed two or three times in a
    /// sitting, and a cup evaluated late can be nearer the next brew than
    /// its own. Several cups in one sitting pair with its brews in order.
    ///
    /// `evaluations` and `brews` of one bag, in any order.
    public static func autoLinks(_ evaluations: [CupEvaluation], brews: [LoggedBrew]) -> [String: String] {
        let byHand = Set(evaluations.filter(\.linkedByHand).compactMap(\.brewID))
        let brews = brews.filter { !byHand.contains($0.id) }.sorted { ($0.timestamp, $0.id) < ($1.timestamp, $1.id) }
        // Newest cup first, each taking a brew before the later cup's, so
        // the pairs keep their order
        var before = brews.endIndex
        var links: [String: String] = [:]
        for cup in evaluations.filter({ !$0.linkedByHand }).sorted(by: { ($0.timestamp, $0.id) > ($1.timestamp, $1.id) }) {
            guard
                let index = brews[..<before].lastIndex(where: {
                    $0.timestamp <= cup.timestamp && $0.timestamp >= cup.timestamp - window
                })
            else { continue }
            links[cup.id] = brews[index].id
            before = index
        }
        return links
    }
}

/// A field where the recipe typed with an evaluation differs from its
/// imported brew.
public struct RecipeDifference: Hashable, Sendable {
    public var field: String
    public var typed: String?
    public var imported: String
}

extension BrewRecipe {
    /// Where `imported` says something else than this recipe, one entry per
    /// field. A field the brew didn't record isn't a difference, and brew
    /// time isn't kept with an evaluation.
    public func differences(from imported: BrewRecipe) -> [RecipeDifference] {
        Self.fields.compactMap { field in
            guard let theirs = field.text(imported), field.text(self) != theirs else { return nil }
            if field.name == "Grind", let mine = grindValue, let theirs = imported.grindValue, mine == theirs { return nil }
            return RecipeDifference(field: field.name, typed: field.text(self), imported: theirs)
        }
    }

    /// This recipe with every field `imported` recorded taken from it.
    public func usingImported(_ imported: BrewRecipe) -> BrewRecipe {
        var recipe = self
        recipe.grinder = imported.grinder ?? grinder
        recipe.grindSetting = imported.grindSetting ?? grindSetting
        recipe.temperatureC = imported.temperatureC ?? temperatureC
        recipe.doseGrams = imported.doseGrams ?? doseGrams
        recipe.waterGrams = imported.waterGrams ?? waterGrams
        recipe.method = imported.method ?? method
        recipe.water = imported.water ?? water
        recipe.profile = imported.profile ?? profile
        return recipe
    }

    private struct Field {
        var name: String
        var text: (BrewRecipe) -> String?
    }

    private static var fields: [Field] {
        [
            Field(name: "Grinder") { $0.grinder },
            Field(name: "Grind") { $0.grindSetting },
            Field(name: "Temperature") { $0.temperatureC.map { "\(number($0)) °C" } },
            Field(name: "Dose") { $0.doseGrams.map { "\(number($0)) g" } },
            Field(name: "Water") { $0.waterGrams.map { "\(number($0)) g" } },
            Field(name: "Method") { $0.method },
            Field(name: "Water recipe") { $0.water },
            Field(name: "Profile") { $0.profile },
        ]
    }
}
