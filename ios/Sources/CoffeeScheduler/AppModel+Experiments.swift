import CoffeeCore
import Foundation
import os

extension AppModel {
    // MARK: - Dial-in experiments

    /// The bag's experiments, newest first.
    func experiments(forBean id: String) -> [SavedExperiment] {
        (try? store?.experiments(beanID: id)) ?? []
    }

    /// Let a newly saved cup decide the bag's open experiment. Returns the
    /// experiment once decided; nil when there's none open or the cup
    /// didn't test it.
    func decideExperiment(with cup: CupEvaluation) -> SavedExperiment? {
        var decided: SavedExperiment?
        if let error = saveFromForm({ decided = try $0.decideOpenExperiment(with: cup) }) {
            Log.store.error("Couldn't decide the experiment for \(cup.id, privacy: .public): \(error, privacy: .public)")
        }
        return decided
    }

    /// Keep an experiment as the bag's next, after `cup`. Returns an error message, or nil once saved.
    func saveExperiment(_ experiment: DialInExperiment, after cup: CupEvaluation) -> String? {
        let saved = SavedExperiment(
            beanID: cup.beanID, createdFrom: cup.id, createdAt: cup.timestamp, start: cup.recipe, experiment: experiment)
        return saveFromForm { try $0.saveExperiment(saved) }
    }

    /// Returns an error message, or nil once dismissed.
    func dismissExperiment(id: String) -> String? {
        saveFromForm { try $0.dismissExperiment(id: id) }
    }

    /// The grinder a cup was ground on, for sizing a change by hand.
    func grinder(for cup: CupEvaluation) -> GrinderSetting? {
        try? cup.recipe.brew.grinder.flatMap { try store?.grinderSetting($0) }
    }
}
