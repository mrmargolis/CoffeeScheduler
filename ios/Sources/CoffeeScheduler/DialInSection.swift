import CoffeeCore
import SwiftUI

/// The bag's dial-in: a button to evaluate a cup, and the cups evaluated so
/// far, newest first, each with what changed in the recipe since the one
/// before. Tapping a cup edits it.
struct DialInSection: View {
    let evaluations: [CupEvaluation]
    var experiments: [SavedExperiment] = []
    /// The newest cup, when it was marked dialed in.
    var dialedIn: CupEvaluation?
    /// Another bag from the roaster's dialed-in recipe, shown until this
    /// bag's first evaluation.
    var startingPoint: RoasterStartingPoint?
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
            if let dialedIn {
                DialedInCard(cup: dialedIn)
            } else if evaluations.isEmpty, let startingPoint {
                StartingPointCard(start: startingPoint)
            } else if let open = experiments.first(where: { $0.status == .open }) {
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

/// The recipe the bag is dialed in at, to repeat.
private struct DialedInCard: View {
    let cup: CupEvaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dialed in").font(.footnote.weight(.semibold)).textCase(.uppercase).foregroundStyle(Palette.onTarget)
            Text(cup.recipe.summaryLine).font(.headline)
            Text("Since \(Format.shortDay(cup.date)). Evaluate a cup with another verdict to start dialing again.")
                .font(.footnote)
                .foregroundStyle(Theme.text2)
        }
        .cardBackground(Theme.card)
        .accessibilityElement(children: .combine)
    }
}

/// Where another bag from the roaster ended up, to start this one from.
private struct StartingPointCard: View {
    let start: RoasterStartingPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Starting point").font(.footnote.weight(.semibold)).textCase(.uppercase).foregroundStyle(Theme.text2)
            Text(start.cup.recipe.summaryLine).font(.headline)
            Text(
                "Where \(start.beanName), from the same roaster, was dialed in on \(Format.shortDay(start.cup.date)). Rate a cup of this bag for advice on it."
            )
            .font(.footnote)
            .foregroundStyle(Theme.text2)
        }
        .cardBackground(Theme.card)
        .accessibilityElement(children: .combine)
    }
}

extension CupRecipe {
    /// "Femobook A4Z 1.6 · 93 °C · … · low agitation"
    var summaryLine: String {
        let parts = brew.summaryParts + [agitation.map { "\($0.name.lowercased()) agitation" }].compactMap { $0 }
        return parts.isEmpty ? "Recipe not recorded" : parts.joined(separator: " · ")
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
        case .better, .dialedIn: Theme.ready
        case .same: Theme.text2
        case .worse: Theme.gapText
        }
    }
}
