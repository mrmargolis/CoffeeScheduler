import CoffeeCore
import Foundation
import os

extension AppModel {
    // MARK: - Dial-in

    /// The bag's cup evaluations, newest first.
    func evaluations(forBean id: String) -> [CupEvaluation] {
        guard let store else { return [] }
        do {
            return try store.evaluations(beanID: id)
        } catch {
            Log.store.error("Couldn't read the evaluations of \(id, privacy: .public): \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// A new evaluation of the bag as of now, starting from its current recipe.
    func newEvaluation(forBean id: String) -> CupEvaluation {
        let recipe = (try? store?.currentRecipe(beanID: id)) ?? CupRecipe()
        return CupEvaluation.new(beanID: id, at: Date(), recipe: recipe)
    }

    /// Save an evaluation. Returns an error message for the form, or nil once saved.
    func saveEvaluation(_ evaluation: CupEvaluation) -> String? {
        saveFromForm { try $0.saveEvaluation(evaluation) }
    }

    /// Delete an evaluation. Returns an error message for the form, or nil once deleted.
    func deleteEvaluation(id: String) -> String? {
        saveFromForm { try $0.deleteEvaluation(id: id) }
    }
}
