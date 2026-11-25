import CoffeeCore
import SwiftUI

/// The bag's dial-in: a button to evaluate a cup, and the cups evaluated so
/// far, newest first, each with what changed in the recipe since the one
/// before. Tapping a cup edits it.
struct DialInSection: View {
    let evaluations: [CupEvaluation]
    var experiments: [SavedExperiment] = []
    /// False when the bag was brewed lately only with methods turned off
    /// for dial-in in Settings.
    var isAvailable = true
    let start: () -> Void
    let edit: (CupEvaluation) -> Void
    var dismissExperiment: (SavedExperiment) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Dial-in", detail: evaluations.isEmpty ? nil : cupCount)
                .padding(.horizontal, 4)
                .padding(.top, 2)
            if let open = experiments.first(where: { $0.status == .open }) {
                OpenExperimentCard(experiment: open) { dismissExperiment(open) }
            }
            if isAvailable {
                evaluateButton
            } else {
                Text("Dial-in advice is for pour-over. This bag was brewed with methods turned off in Settings › Dial-in.")
                    .font(.footnote)
                    .foregroundStyle(Theme.text2)
                    .cardBackground(Theme.card)
            }

            ForEach(Array(evaluations.enumerated()), id: \.element.id) { index, evaluation in
                let previous = index + 1 < evaluations.count ? evaluations[index + 1] : nil
                Button {
                    edit(evaluation)
                } label: {
                    EvaluationRow(
                        evaluation: evaluation, changes: previous.map { evaluation.recipe.changes(from: $0.recipe) } ?? [],
                        decided: experiments.first { $0.decidedBy == evaluation.id })
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edits this evaluation")
            }
        }
    }

    private var evaluateButton: some View {
        Button(action: start) {
            Label("Evaluate a cup", systemImage: "cup.and.saucer")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.ground)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.tileRadius))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Rates the cup you just drank against what you want from this coffee")
    }

    private var cupCount: String {
        "\(evaluations.count) \(evaluations.count == 1 ? "cup" : "cups")"
    }
}

/// The bag's open experiment: what to try on the next cup, until a cup
/// tests it or it's dismissed.
private struct OpenExperimentCard: View {
    let experiment: SavedExperiment
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Next cup").font(.footnote.weight(.semibold)).textCase(.uppercase).foregroundStyle(Theme.accent)
                Spacer()
                Button("Dismiss", action: dismiss).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text2)
                    .accessibilityHint("Drops this experiment")
            }
            Text(experiment.experiment.instruction).font(.headline)
            Text("Taste for: \(experiment.experiment.expectedEffect.lowercased()).").font(.footnote).foregroundStyle(Theme.text2)
        }
        .cardBackground(Theme.card)
    }
}

/// One evaluated cup: when, the verdict, what changed, its chart and the
/// drawdown.
private struct EvaluationRow: View {
    let evaluation: CupEvaluation
    let changes: [String]
    /// The experiment this cup decided.
    var decided: SavedExperiment?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Format.shortDay(evaluation.date)) · \(time)").font(.subheadline.weight(.semibold))
                Spacer()
                if let verdict = evaluation.verdict {
                    Text(verdict.name).font(.footnote.weight(.semibold)).foregroundStyle(verdictColor(verdict))
                }
            }
            if !changes.isEmpty {
                Text(changes.joined(separator: " · ")).font(.footnote).foregroundStyle(Theme.accent)
            }
            if let decided, let outcome = decided.outcome {
                HStack(spacing: 6) {
                    Text("\(decided.experiment.move.name):").foregroundStyle(Theme.text2)
                    Text(outcome.name).fontWeight(.semibold).foregroundStyle(outcome.color)
                }
                .font(.footnote)
            }
            CupChartView(ratings: evaluation.ratings)
            tags
            if let notes = evaluation.notes {
                Text(notes).font(.footnote).foregroundStyle(Theme.text2).lineLimit(4)
            }
            if let flow = flowText {
                Text(flow).font(.footnote).foregroundStyle(Theme.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(Theme.card)
        .accessibilityElement(children: .combine)
    }

    /// Character tags in amber, since they're problems; flavours plain.
    @ViewBuilder
    private var tags: some View {
        let character = CharacterTag.allCases.filter { evaluation.character[$0] != nil }
        if !character.isEmpty || !evaluation.flavours.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(character, id: \.self) { tag in
                    Badge(text: tag.name, color: Palette.offTarget, background: Palette.offTarget.opacity(0.16))
                }
                ForEach(evaluation.flavours, id: \.self) { flavour in
                    Badge(text: flavour, color: Theme.text, background: Theme.raised)
                }
            }
        }
    }

    private var flowText: String? {
        let parts = [evaluation.drawdown.map { "\($0.name) drawdown" }, evaluation.flowProblem ? "stalled or channelled" : nil]
        let text = parts.compactMap { $0 }.joined(separator: ", ")
        return text.isEmpty ? nil : text.prefix(1).uppercased() + text.dropFirst()
    }

    private var time: String {
        Date(timeIntervalSince1970: evaluation.timestamp).formatted(date: .omitted, time: .shortened)
    }

    private func verdictColor(_ verdict: Verdict) -> Color {
        switch verdict {
        case .better: Theme.ready
        case .same: Theme.text2
        case .worse: Theme.gapText
        }
    }
}
