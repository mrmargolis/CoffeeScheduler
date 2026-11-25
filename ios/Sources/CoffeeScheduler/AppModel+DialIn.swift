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

extension AppModel {
    /// Flavours used on any evaluation, most used first, for quick reuse.
    func usedFlavours() -> [String] {
        (try? store?.usedFlavours()) ?? []
    }
}

extension AppModel {
    /// Every brew method from the imports, with whether it gets dial-in advice.
    func dialInMethods() -> [DialInMethod] {
        (try? store?.dialInMethods()) ?? []
    }

    /// Turn dial-in advice on or off for a method. Returns an error message, or nil once saved.
    func setDialIn(method: String, on: Bool) -> String? {
        saveFromForm { try $0.setDialIn(method: method, on: on) }
    }

    /// Whether the bag was brewed lately with a method that gets dial-in advice.
    func bagUsesDialInMethod(_ id: String) -> Bool {
        (try? store?.bagUsesDialInMethod(beanID: id)) ?? true
    }
}

extension AppModel {
    /// Every grinder from the imports, with its step, direction and usual range.
    func grinderSettings() -> [GrinderSetting] {
        (try? store?.grinderSettings()) ?? []
    }

    /// Save a grinder's step (nil for the usual one) and direction. Returns an error message, or nil once saved.
    func setGrinder(_ name: String, step: Double?, higherIsCoarser: Bool) -> String? {
        saveFromForm { try $0.setGrinder(name, step: step, higherIsCoarser: higherIsCoarser) }
    }

    func temperatureStep() -> Double {
        (try? store?.temperatureStep()) ?? CoffeeStore.defaultTemperatureStep
    }

    /// Returns an error message, or nil once saved.
    func setTemperatureStep(_ step: Double) -> String? {
        saveFromForm { try $0.setTemperatureStep(step) }
    }
}

extension AppModel {
    /// Advice on a cup, from it and the bag's earlier cups, sized for the
    /// grinder it was ground on.
    func advice(for evaluation: CupEvaluation) -> DialInAdvice {
        guard let store else { return DialInAdvisor.advise([evaluation], context: DialInContext()) }
        do {
            let earlier = try store.evaluations(beanID: evaluation.beanID)
                .filter { $0.id != evaluation.id && $0.timestamp <= evaluation.timestamp }
                .reversed()
            let brew = evaluation.recipe.brew
            let context = DialInContext(
                grinder: try brew.grinder.flatMap { try store.grinderSetting($0) },
                temperatureStep: try store.temperatureStep(),
                isDialInMethod: try store.isDialInMethod(brew.method),
                blocked: try store.blockedVariables(beanID: evaluation.beanID, grinder: brew.grinder, method: brew.method))
            return DialInAdvisor.advise(earlier + [evaluation], context: context)
        } catch {
            Log.store.error("Couldn't advise on \(evaluation.id, privacy: .public): \(String(describing: error), privacy: .public)")
            return DialInAdvisor.advise([evaluation], context: DialInContext())
        }
    }
}

extension AppModel {
    /// The bag's newest cup, when it was marked dialed in.
    func dialedInCup(forBean id: String) -> CupEvaluation? {
        try? store?.dialedInCup(beanID: id)
    }
}
