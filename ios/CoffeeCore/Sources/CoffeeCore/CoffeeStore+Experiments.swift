import Foundation

extension CoffeeStore {
    // MARK: - Dial-in experiments

    /// Keep an experiment. A new open one supersedes any the bag already has
    /// open, so there's never more than one.
    public func saveExperiment(_ experiment: SavedExperiment) throws {
        try db.transaction {
            if experiment.status == .open {
                try db.run(
                    "UPDATE dial_in_experiments SET status = 'superseded' WHERE bean_id = ? AND status = 'open' AND id != ?",
                    [.text(experiment.beanID), .text(experiment.id)])
            }
            try db.run(
                """
                INSERT OR REPLACE INTO dial_in_experiments
                  (id, bean_id, created_from, created_at, start_recipe, experiment, status, outcome, decided_by)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(experiment.id), .text(experiment.beanID), .text(experiment.createdFrom), .double(experiment.createdAt),
                    .text(try Self.json(experiment.start)), .text(try Self.json(experiment.experiment)),
                    .text(experiment.status.rawValue), SQLValue(experiment.outcome?.rawValue), SQLValue(experiment.decidedBy),
                ])
        }
    }

    /// The bag's experiments, newest first.
    public func experiments(beanID: String) throws -> [SavedExperiment] {
        try db.query(
            "SELECT * FROM dial_in_experiments WHERE bean_id = ? ORDER BY created_at DESC, id DESC", [.text(beanID)]
        ).compactMap(Self.experiment)
    }

    public func openExperiment(beanID: String) throws -> SavedExperiment? {
        try experiments(beanID: beanID).first { $0.status == .open }
    }

    public func dismissExperiment(id: String) throws {
        try db.run("UPDATE dial_in_experiments SET status = 'dismissed' WHERE id = ? AND status = 'open'", [.text(id)])
    }

    /// Let a new cup decide the bag's open experiment. Returns it once
    /// decided; nil when there's none open, or the cup didn't test it (it
    /// stays open). A decision is kept as it is, even if the cup is edited.
    @discardableResult
    public func decideOpenExperiment(with cup: CupEvaluation) throws -> SavedExperiment? {
        guard var open = try openExperiment(beanID: cup.beanID), open.createdFrom != cup.id, cup.timestamp > open.createdAt,
            let outcome = open.outcome(of: cup)
        else { return nil }
        open.status = .decided
        open.outcome = outcome
        open.decidedBy = cup.id
        try saveExperiment(open)
        return open
    }

    /// Variables the advisor shouldn't suggest for this bag on this gear.
    public func blockedVariables(beanID: String, grinder: String?, method: String?) throws -> Set<DialInVariable> {
        DialInLimits.blocked(try experiments(beanID: beanID), grinder: grinder, method: method)
    }

    private static func experiment(_ row: SQLRow) -> SavedExperiment? {
        let decoder = JSONDecoder()
        guard let id = row.string("id"), let beanID = row.string("bean_id"), let createdFrom = row.string("created_from"),
            let createdAt = row.double("created_at"),
            let start = row.string("start_recipe").flatMap({ try? decoder.decode(CupRecipe.self, from: Data($0.utf8)) }),
            let experiment = row.string("experiment").flatMap({ try? decoder.decode(DialInExperiment.self, from: Data($0.utf8)) }),
            let status = row.string("status").flatMap(ExperimentStatus.init(rawValue:))
        else { return nil }
        return SavedExperiment(
            id: id, beanID: beanID, createdFrom: createdFrom, createdAt: createdAt, start: start, experiment: experiment,
            status: status, outcome: row.string("outcome").flatMap(ExperimentOutcome.init(rawValue:)), decidedBy: row.string("decided_by"))
    }

    private static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(bytes: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }
}
