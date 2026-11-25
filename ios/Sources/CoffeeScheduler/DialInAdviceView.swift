import CoffeeCore
import SwiftUI

/// What the advisor says after a cup is saved: the cup's chart, what's off,
/// and the one change to try next, with what to taste for and what to do
/// after.
struct DialInAdviceView: View {
    let evaluation: CupEvaluation
    let advice: DialInAdvice

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        case .nothingToChange:
            message("Nothing to change", "Keep this recipe. If it's how you want it, mark the next cup dialed in.")
        case .noSuggestion:
            message("No change to suggest", "None of the dial-in rules fit this cup, or the change they'd make is out of range.")
        case .notADialInMethod:
            message("No advice for this method", "Dial-in advice is for the methods turned on in Settings › Dial-in.")
        case .nothingRated:
            message("Nothing rated", "Rate a few attributes for a suggestion.")
        }
    }

    private func message(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(Theme.text2)
        }
        .cardBackground(Theme.card)
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
