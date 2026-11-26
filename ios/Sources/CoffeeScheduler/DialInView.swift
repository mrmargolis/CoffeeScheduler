import CoffeeCore
import SwiftUI

/// The Dial-in tab: judge a cup against the one you want, and get one change
/// to try next. A tool, not a log: nothing is saved, and Clear starts over.
struct DialInView: View {
    @State private var cup: CupTasting

    /// Starts from `cup`, for the screenshots; the tab starts empty.
    init(cup: CupTasting = CupTasting()) {
        _cup = State(initialValue: cup)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Rate the cup against the one you want. Leave out anything you didn't judge.")
                        .font(.footnote)
                        .foregroundStyle(Theme.text2)
                    ratings
                    ChoiceRow(title: "Drawdown", choices: Drawdown.allCases, name: \.name, selection: $cup.drawdown)
                    tags
                    agitation
                    tried
                    DialInAdviceCard(advice: DialInAdvisor.advise(cup))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Theme.ground)
            .foregroundStyle(Theme.text)
            .navigationTitle("Dial-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { withAnimation(.snappy) { cup = CupTasting() } }
                        .disabled(cup == CupTasting())
                }
            }
        }
    }

    private var ratings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Too little")
                Spacer()
                Text("Ideal")
                Spacer()
                Text("Too much")
            }
            .font(.caption)
            .foregroundStyle(Theme.text3)
            .accessibilityHidden(true)
            ForEach(SensoryAttribute.allCases, id: \.self) { attribute in
                RatingRow(attribute: attribute, value: $cup.ratings[attribute])
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.tileRadius))
    }

    private var tags: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tasted").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(CharacterTag.allCases, id: \.self) { tag in
                    let on = cup.character.contains(tag)
                    Chip(text: tag.name, isOn: on, fills: true) {
                        if on { cup.character.remove(tag) } else { cup.character.insert(tag) }
                    }
                }
            }
        }
    }

    private var agitation: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChoiceRow(title: "Agitation", choices: Agitation.allCases, name: \.name, selection: $cup.agitation)
            Text("Optional: how much you used, so it won't suggest less than low or more than high.")
                .font(.caption)
                .foregroundStyle(Theme.text3)
        }
    }

    /// Changes that haven't helped this coffee, so the advice moves on.
    private var tried: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Already tried").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(DialInVariable.allCases, id: \.self) { variable in
                    let on = cup.tried.contains(variable)
                    Chip(text: variable.name, isOn: on, fills: true) {
                        if on { cup.tried.remove(variable) } else { cup.tried.insert(variable) }
                    }
                    .accessibilityLabel("Already tried: \(variable.name)")
                }
            }
            Text("Changes that didn't help this coffee, in either direction. They won't be suggested.")
                .font(.caption)
                .foregroundStyle(Theme.text3)
        }
    }
}

/// What's off, and the one change to try next with what to do after.
struct DialInAdviceCard: View {
    let advice: DialInAdvice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Advice").font(.footnote.weight(.semibold)).textCase(.uppercase).foregroundStyle(Theme.accent)
            if !advice.diagnosis.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(advice.diagnosis, id: \.self) { Text($0) }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.text2)
            }
            next
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(Theme.card)
    }

    @ViewBuilder
    private var next: some View {
        switch advice.next {
        case .change(let suggestion):
            VStack(alignment: .leading, spacing: 8) {
                Text("Next cup").font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(Theme.text3)
                Text(suggestion.instruction).font(.title3.weight(.semibold))
                Text("Taste for: \(suggestion.expectedEffect.lowercased()).").font(.subheadline)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(suggestion.criteria, id: \.result) { criterion in
                        (Text("\(criterion.result): ").fontWeight(.semibold) + Text(criterion.next))
                            .font(.footnote)
                            .foregroundStyle(Theme.text2)
                    }
                }
                .padding(.top, 2)
            }
        case .nothingToChange:
            Text("Keep this recipe.").font(.title3.weight(.semibold)).foregroundStyle(Theme.ready)
        case .noSuggestion:
            Text("No single change stands out. Rate more of the cup, or untick a change you've tried.")
                .font(.subheadline)
        case .nothingRated:
            Text("Rate the cup above to get a suggestion.").font(.subheadline).foregroundStyle(Theme.text3)
        }
    }
}
