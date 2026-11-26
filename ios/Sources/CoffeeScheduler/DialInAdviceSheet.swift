import CoffeeCore
import SwiftUI

/// The whole advice, opened from the bar: the change and what to taste
/// for, why, what the tool saw, and what to do after the next cup. It opens
/// just tall enough to show all of it, and scrolls at large text sizes.
struct DialInAdviceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let advice: DialInAdvice
    /// The advice's measured height; 0 until it's laid out.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(advice.suggestion == nil ? "Advice" : "Next cup")
                        .font(.footnote.weight(.bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.accent)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                }
                headline
                if let suggestion = advice.suggestion {
                    why(suggestion)
                }
                if !advice.diagnosis.isEmpty {
                    section("What it saw") {
                        Text(advice.diagnosis.joined(separator: " ")).font(.subheadline).foregroundStyle(Theme.text2)
                    }
                }
                if let suggestion = advice.suggestion {
                    section("After the next cup") { criteria(suggestion) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                contentHeight = $0
            }
        }
        .foregroundStyle(Theme.text)
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight + 12), .large] : [.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    @ViewBuilder
    private var headline: some View {
        switch advice.next {
        case .change(let suggestion):
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.instruction).font(.title2.bold())
                Text("Taste for: \(suggestion.expectedEffect.lowercased()).").font(.body)
                if suggestion.confidence == .low {
                    Label("Exploratory: a guess worth testing, not a diagnosis", systemImage: "flask")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 2)
                }
            }
        case .nothingToChange:
            Text("Keep this recipe.").font(.title2.bold()).foregroundStyle(Theme.ready)
        case .noSuggestion:
            Text("No single change stands out. Rate more of the cup, or untick a change you've tried.").font(.body)
        case .nothingRated:
            Text("Rate the cup to get a suggestion.").font(.body).foregroundStyle(Theme.text3)
        }
    }

    private func why(_ suggestion: DialInSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Why").font(.caption.weight(.semibold)).foregroundStyle(Theme.text3)
            Text(suggestion.why).font(.subheadline).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14))
    }

    private func criteria(_ suggestion: DialInSuggestion) -> some View {
        VStack(spacing: 0) {
            ForEach(suggestion.criteria, id: \.result) { criterion in
                Divider().overlay(Theme.hairline)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(Self.shortResult(criterion.result))
                        .fontWeight(.semibold)
                        .foregroundStyle(criterion.result == "Better" ? Theme.ready : criterion.result == "Worse" ? Theme.gapText : Theme.text)
                        .frame(width: 92, alignment: .leading)
                    Text(criterion.next).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.text3).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// "Overshot: too far the other way" → "Overshot", to fit the column.
    private static func shortResult(_ result: String) -> String {
        String(result.prefix { $0 != ":" })
    }
}
