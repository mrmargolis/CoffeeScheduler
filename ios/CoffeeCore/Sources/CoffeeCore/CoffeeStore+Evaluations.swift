import Foundation

extension CoffeeStore {
    // MARK: - Cup evaluations

    /// Save an evaluation, new or edited. Text is trimmed, and blank is unknown.
    public func saveEvaluation(_ evaluation: CupEvaluation) throws {
        let recipe = evaluation.recipe.brew.trimmed()
        let rating = { SQLValue(CupRating.clamped(evaluation.ratings[$0])) }
        try db.run(
            """
            INSERT OR REPLACE INTO cup_evaluations (
              id, bean_id, evaluated_at, evaluated_on, grinder, grind_setting, temperature_c, dose_grams, water_grams,
              method, water, profile, agitation, acidity, sweetness, intensity, clarity, body, finish,
              drawdown, flow_problem, verdict, character_tags, flavour_tags, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(evaluation.id), .text(evaluation.beanID), .double(evaluation.timestamp), .text(evaluation.date),
                SQLValue(recipe.grinder), SQLValue(recipe.grindSetting), SQLValue(recipe.temperatureC),
                SQLValue(recipe.doseGrams), SQLValue(recipe.waterGrams), SQLValue(recipe.method), SQLValue(recipe.water),
                SQLValue(recipe.profile), SQLValue(evaluation.recipe.agitation?.rawValue),
                rating(.acidity), rating(.sweetness), rating(.intensity), rating(.clarity), rating(.body), rating(.finish),
                SQLValue(evaluation.drawdown?.rawValue), SQLValue(evaluation.flowProblem), SQLValue(evaluation.verdict?.rawValue),
                SQLValue(EvaluationTags.characterJSON(evaluation.character)),
                SQLValue(EvaluationTags.flavoursJSON(evaluation.flavours)),
                SQLValue(EvaluationTags.clean(evaluation.notes)),
            ])
    }

    public func deleteEvaluation(id: String) throws {
        try db.run("DELETE FROM cup_evaluations WHERE id = ?", [.text(id)])
    }

    /// The bag's evaluations, newest first.
    public func evaluations(beanID: String) throws -> [CupEvaluation] {
        try db.query(
            "SELECT * FROM cup_evaluations WHERE bean_id = ? ORDER BY evaluated_at DESC, id DESC",
            [.text(beanID)]
        ).compactMap(Self.evaluation)
    }

    /// The recipe to start a new evaluation from: the newer of the bag's last
    /// evaluation and its last imported brew. Agitation only ever comes from
    /// an evaluation, since BeanConqueror doesn't record it. Brew time isn't
    /// carried over: it's how the last cup went, not something to repeat.
    public func currentRecipe(beanID: String) throws -> CupRecipe {
        let lastEvaluation = try evaluations(beanID: beanID).first
        let lastBrew = try latestBrew(beanID: beanID)
        var recipe: CupRecipe
        if let lastEvaluation, lastEvaluation.timestamp >= lastBrew?.timestamp ?? -.infinity {
            recipe = lastEvaluation.recipe
        } else {
            recipe = CupRecipe(brew: lastBrew?.recipe ?? BrewRecipe(), agitation: lastEvaluation?.recipe.agitation)
        }
        recipe.brew.brewSeconds = nil
        return recipe
    }

    /// Every flavour used on any evaluation, most used first, then A to Z.
    /// Ones that differ only in case count as one, spelled as first used.
    public func usedFlavours() throws -> [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for row in try db.query("SELECT flavour_tags FROM cup_evaluations ORDER BY evaluated_at") {
            for flavour in EvaluationTags.flavours(fromJSON: row.string("flavour_tags")) {
                counts[flavour.lowercased(), default: (flavour, 0)].count += 1
            }
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(\.name)
    }

    private static func evaluation(_ row: SQLRow) -> CupEvaluation? {
        guard let id = row.string("id"), let beanID = row.string("bean_id"), let timestamp = row.double("evaluated_at"),
            let date = row.string("evaluated_on")
        else { return nil }
        var ratings: [SensoryAttribute: Int] = [:]
        for attribute in SensoryAttribute.allCases {
            ratings[attribute] = CupRating.clamped(row.int(attribute.rawValue))
        }
        let brew = BrewRecipe(
            grinder: row.string("grinder"), grindSetting: row.string("grind_setting"), temperatureC: row.double("temperature_c"),
            doseGrams: row.double("dose_grams"), waterGrams: row.double("water_grams"), method: row.string("method"),
            water: row.string("water"), profile: row.string("profile"))
        return CupEvaluation(
            id: id, beanID: beanID, timestamp: timestamp, date: date,
            recipe: CupRecipe(brew: brew, agitation: row.string("agitation").flatMap(Agitation.init(rawValue:))),
            ratings: ratings,
            drawdown: row.string("drawdown").flatMap(Drawdown.init(rawValue:)),
            flowProblem: row.int("flow_problem") == 1,
            verdict: row.string("verdict").flatMap(Verdict.init(rawValue:)),
            character: EvaluationTags.character(fromJSON: row.string("character_tags")),
            flavours: EvaluationTags.flavours(fromJSON: row.string("flavour_tags")),
            notes: row.string("notes"))
    }
}
