import CoffeeCore
import SwiftUI

/// The bag's dial-in: a button to evaluate a cup, and the cups evaluated so
/// far, newest first, each with what changed in the recipe since the one
/// before. Tapping a cup edits it.
struct DialInSection: View {
    let evaluations: [CupEvaluation]
    let start: () -> Void
    let edit: (CupEvaluation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Dial-in", detail: evaluations.isEmpty ? nil : cupCount)
                .padding(.horizontal, 4)
                .padding(.top, 2)
            Button(action: start) {
                Label("Evaluate a cup", systemImage: "cup.and.saucer")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.ground)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.tileRadius))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Rates the cup you just drank against what you want from this coffee")

            ForEach(Array(evaluations.enumerated()), id: \.element.id) { index, evaluation in
                let previous = index + 1 < evaluations.count ? evaluations[index + 1] : nil
                Button {
                    edit(evaluation)
                } label: {
                    EvaluationRow(evaluation: evaluation, changes: previous.map { evaluation.recipe.changes(from: $0.recipe) } ?? [])
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edits this evaluation")
            }
        }
    }

    private var cupCount: String {
        "\(evaluations.count) \(evaluations.count == 1 ? "cup" : "cups")"
    }
}

/// One evaluated cup: when, the verdict, the rated attributes, the drawdown
/// and what changed.
private struct EvaluationRow: View {
    let evaluation: CupEvaluation
    let changes: [String]

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
            ratingLines
            if let flow = flowText {
                Text(flow).font(.footnote).foregroundStyle(Theme.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(Theme.card)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var ratingLines: some View {
        let rated = SensoryAttribute.allCases.compactMap { attribute in evaluation.ratings[attribute].map { (attribute, $0) } }
        if rated.isEmpty {
            Text("Nothing rated").font(.footnote).foregroundStyle(Theme.text3)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(rated, id: \.0) { attribute, value in
                    HStack {
                        Text(attribute.name).foregroundStyle(Theme.text2)
                        Spacer()
                        Text(CupRating.label(value)).foregroundStyle(value == 0 ? Theme.ready : Theme.text)
                    }
                    .font(.footnote)
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
