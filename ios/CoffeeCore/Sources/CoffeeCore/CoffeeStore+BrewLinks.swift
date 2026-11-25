import Foundation

extension CoffeeStore {
    // MARK: - Linking evaluations to brews

    /// How far either side of an evaluation `brews(near:)` looks.
    public static let nearBrewWindow: Double = 12 * 3600

    /// The bag's brews that can be linked: ones imported with their
    /// BeanConqueror ID and time, oldest first.
    public func loggedBrews(beanID: String) throws -> [LoggedBrew] {
        try db.query(
            "SELECT * FROM brews WHERE bean_id = ? AND bc_uuid IS NOT NULL AND logged_at IS NOT NULL ORDER BY logged_at, bc_uuid",
            [.text(beanID)]
        ).compactMap(Self.loggedBrew)
    }

    /// The brew an evaluation is linked to, if it's still imported.
    public func linkedBrew(for evaluation: CupEvaluation) throws -> LoggedBrew? {
        guard let brewID = evaluation.brewID else { return nil }
        return try db.query(
            "SELECT * FROM brews WHERE bean_id = ? AND bc_uuid = ? LIMIT 1", [.text(evaluation.beanID), .text(brewID)]
        ).first.flatMap(Self.loggedBrew)
    }

    /// The bag's brews within `nearBrewWindow` of an evaluation, to link it
    /// to by hand, newest first.
    public func brews(near evaluation: CupEvaluation) throws -> [LoggedBrew] {
        try loggedBrews(beanID: evaluation.beanID)
            .filter { abs($0.timestamp - evaluation.timestamp) <= Self.nearBrewWindow }
            .reversed()
    }

    /// After an import: a link by hand to a brew no longer in the export is
    /// cleared, then every link not made by hand is worked out again.
    func relinkAllEvaluations() throws {
        try db.run(
            """
            UPDATE cup_evaluations SET brew_uuid = NULL, brew_linked_by_hand = 0
            WHERE brew_uuid IS NOT NULL AND NOT EXISTS (
              SELECT 1 FROM brews WHERE brews.bean_id = cup_evaluations.bean_id AND brews.bc_uuid = cup_evaluations.brew_uuid)
            """)
        for row in try db.query("SELECT DISTINCT bean_id FROM cup_evaluations") {
            if let beanID = row.string("bean_id") { try relinkEvaluations(beanID: beanID) }
        }
    }

    /// Link each of the bag's evaluations not linked by hand (BrewLinker).
    func relinkEvaluations(beanID: String) throws {
        let evaluations = try evaluations(beanID: beanID)
        let links = BrewLinker.autoLinks(evaluations, brews: try loggedBrews(beanID: beanID))
        for evaluation in evaluations where !evaluation.linkedByHand && links[evaluation.id] != evaluation.brewID {
            try db.run(
                "UPDATE cup_evaluations SET brew_uuid = ? WHERE id = ?", [SQLValue(links[evaluation.id]), .text(evaluation.id)])
        }
    }

    private static func loggedBrew(_ row: SQLRow) -> LoggedBrew? {
        guard let id = row.string("bc_uuid"), let beanID = row.string("bean_id"), let timestamp = row.double("logged_at") else {
            return nil
        }
        return LoggedBrew(
            id: id, beanID: beanID, timestamp: timestamp, recipe: brewRecipe(row), rating: row.double("rating"),
            notes: row.string("notes"))
    }
}
