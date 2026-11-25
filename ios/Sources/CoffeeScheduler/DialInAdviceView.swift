import CoffeeCore
import SwiftUI

/// What the advisor says after a cup is saved: the cup's chart, what's off,
/// and the one change to try next, with what to taste for and what to do
/// after.
struct DialInAdviceView: View {
    @Environment(AppModel.self) private var model
    let evaluation: CupEvaluation
    let advice: DialInAdvice
    /// The experiment this cup decided, if any.
    var decided: SavedExperiment?
    /// The bag's open experiment, when this cup didn't test it.
    var stillOpen: SavedExperiment?
    @State private var savedNext: DialInExperiment?
    @State private var choosesOwn = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let decided { ExperimentResult(experiment: decided) }
            if let stillOpen {
                note("Still to try: \(stillOpen.experiment.instruction). This cup didn't make that change, so it stays open.")
            }
            CupChartView(ratings: evaluation.ratings).cardBackground(Theme.card)
            if !advice.diagnosis.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(title: "Diagnosis")
                    ForEach(advice.diagnosis, id: \.self) { line in
                        Text(line).font(.subheadline)
                    }
                }
            }
            next
        }
    }

    @ViewBuilder
    private var next: some View {
        switch advice.next {
        case .experiment(let experiment):
            ExperimentCard(experiment: experiment)
            actions(for: experiment)
        case .nothingToChange:
            message("Nothing to change", "Keep this recipe. If it's how you want it, mark the next cup dialed in.")
        case .noSuggestion:
            message("No change to suggest", "None of the dial-in rules fit this cup, or the change they'd make is out of range.")
        case .notADialInMethod:
            message("No advice for this method", "Dial-in advice is for the methods turned on in Settings › Dial-in.")
        case .nothingRated:
            message("Nothing rated", "Rate a few attributes for a suggestion.")
        case .dialedIn:
            message("Dialed in", "Keep this recipe. It's at the top of the bag's dial-in until a cup says otherwise.")
        }
    }

    /// Keep the suggestion, or choose a change instead.
    @ViewBuilder
    private func actions(for experiment: DialInExperiment) -> some View {
        if let savedNext {
            note("Saved for the next cup: \(savedNext.instruction). It's on the bag's page until a cup tests it.")
        } else if choosesOwn {
            OwnExperimentEditor(cup: evaluation, grinder: model.grinder(for: evaluation)) { keep($0) }
        } else {
            HStack(spacing: 10) {
                Button("Try this next") { keep(experiment) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.ground)
                Button("Something else") { choosesOwn = true }
                    .buttonStyle(.bordered)
                    .tint(Theme.text2)
            }
            .font(.callout.weight(.semibold))
        }
        if let error {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.gapText)
        }
    }

    private func keep(_ experiment: DialInExperiment) {
        error = model.saveExperiment(experiment, after: evaluation)
        if error == nil { savedNext = experiment }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Theme.text2)
    }

    private func message(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(Theme.text2)
        }
        .cardBackground(Theme.card)
    }
}

/// How the last experiment went, decided by this cup.
struct ExperimentResult: View {
    let experiment: SavedExperiment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: "Last experiment")
            Text(experiment.experiment.instruction).font(.subheadline)
            if let outcome = experiment.outcome {
                Text(outcome.name).font(.headline).foregroundStyle(outcome.color)
                Text(outcome.explanation).font(.footnote).foregroundStyle(Theme.text2)
            }
        }
        .cardBackground(Theme.card)
    }
}

extension ExperimentOutcome {
    var color: Color {
        switch self {
        case .improved: Palette.onTarget
        case .worse: Theme.gapText
        case .unchanged, .confounded, .notComparable: Theme.text2
        }
    }

    var explanation: String {
        switch self {
        case .improved: "What it aimed at moved toward the cup you want."
        case .unchanged: "What it aimed at didn't move much either way."
        case .worse: "Something it aimed at moved further from the cup you want."
        case .confounded: "Something else in the recipe changed too, so this cup can't say what the change did."
        case .notComparable: "This cup was brewed on a different grinder or with a different method."
        }
    }
}

/// The next experiment: the change, what to taste for, and what to do after.
struct ExperimentCard: View {
    let experiment: DialInExperiment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Next cup")
            Text(experiment.instruction).font(.title3.weight(.semibold))
            Text("Taste for: \(experiment.expectedEffect.prefix(1).lowercased() + experiment.expectedEffect.dropFirst()).")
                .font(.subheadline)
                .foregroundStyle(Theme.text2)
            if experiment.to == nil {
                Text("Set a step for this grinder in Settings › Dial-in for an exact setting.")
                    .font(.footnote)
                    .foregroundStyle(Theme.text3)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(experiment.criteria, id: \.result) { criterion in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(criterion.result).foregroundStyle(Theme.text2).frame(width: 110, alignment: .leading)
                        Text(criterion.next)
                    }
                    .font(.footnote)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .cardBackground(Theme.card)
    }
}
