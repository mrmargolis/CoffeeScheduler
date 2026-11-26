import CoffeeCore
import SwiftUI

/// The Dial-in tab: judge a cup against the one you want, and get one change
/// to try next. A tool, not a log: nothing is saved, and Clear starts over.
/// The form fits one screen; the advice is a bar under it that updates as
/// you rate, and opens into the whole of it.
struct DialInView: View {
    @State private var cup: CupTasting
    @State private var showsAdvice: Bool

    /// Starts from `cup`, for the screenshots; the tab starts empty.
    init(cup: CupTasting = CupTasting(), showsAdvice: Bool = false) {
        _cup = State(initialValue: cup)
        _showsAdvice = State(initialValue: showsAdvice)
    }

    var body: some View {
        let advice = DialInAdvisor.advise(cup)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ratings
                    HStack(alignment: .top, spacing: 12) {
                        SegmentedChoice(
                            title: "Drawdown", choices: Drawdown.allCases, label: \.name, name: \.name, selection: $cup.drawdown)
                        SegmentedChoice(
                            title: "Agitation", note: "optional", choices: Agitation.allCases, label: \.shortName, name: \.name,
                            selection: $cup.agitation)
                    }
                    tags
                    tried
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom) {
                DialInAdviceBar(advice: advice) { showsAdvice = true }
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
            .sheet(isPresented: $showsAdvice) {
                DialInAdviceSheet(advice: advice)
            }
        }
    }

    private var ratings: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("vs. the cup you want").frame(width: ratingNameWidth, alignment: .leading)
                Text("Too little")
                Spacer()
                Text("Ideal")
                Spacer()
                Text("Too much")
            }
            .font(.caption2)
            .foregroundStyle(Theme.text3)
            .padding(.bottom, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rate each against the cup you want: too little, ideal, or too much")
            ForEach(SensoryAttribute.allCases, id: \.self) { attribute in
                if attribute != SensoryAttribute.allCases.first { Divider().overlay(Theme.hairline) }
                RatingRow(attribute: attribute, value: $cup.ratings[attribute])
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.tileRadius))
    }

    private var tags: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Tasted")
            FlowLayout(spacing: 8) {
                ForEach(CharacterTag.allCases, id: \.self) { tag in
                    let on = cup.character.contains(tag)
                    Chip(text: tag.name, isOn: on) {
                        if on { cup.character.remove(tag) } else { cup.character.insert(tag) }
                    }
                }
            }
        }
    }

    /// Changes that haven't helped this coffee, so the advice moves on.
    private var tried: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                heading("Already tried")
                Spacer()
                Text("won't be suggested").font(.caption).foregroundStyle(Theme.text3)
            }
            HStack(spacing: 8) {
                ForEach(DialInVariable.allCases, id: \.self) { variable in
                    let on = cup.tried.contains(variable)
                    Chip(text: variable.shortName, isOn: on, fills: true) {
                        if on { cup.tried.remove(variable) } else { cup.tried.insert(variable) }
                    }
                    .accessibilityLabel("Already tried: \(variable.name)")
                }
            }
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text2).accessibilityAddTraits(.isHeader)
    }
}

/// The advice in one line, under the form: the change to try, or what
/// there is instead. Tapping it opens the whole advice.
struct DialInAdviceBar: View {
    let advice: DialInAdvice
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(advice.suggestion == nil ? "Advice" : "Next cup")
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.accent)
                    Text(headline)
                        .font(.headline)
                        .foregroundStyle(advice.next == .nothingRated ? Theme.text3 : headlineColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                if advice.next != .nothingRated {
                    HStack(spacing: 4) {
                        Text("Why")
                        Image(systemName: "chevron.up").font(.caption.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.text2)
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(minHeight: 62)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.tileRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.tileRadius).strokeBorder(Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(advice.next == .nothingRated)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.ground)
        .accessibilityHint("Shows the whole advice")
    }

    private var headline: String {
        switch advice.next {
        case .change(let suggestion): suggestion.instruction
        case .nothingToChange: "Keep this recipe"
        case .noSuggestion: "No single change stands out"
        case .nothingRated: "Rate the cup to get a suggestion"
        }
    }

    private var headlineColor: Color {
        advice.next == .nothingToChange ? Theme.ready : Theme.text
    }
}
