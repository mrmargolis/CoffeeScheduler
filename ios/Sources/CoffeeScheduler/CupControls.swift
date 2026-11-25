import CoffeeCore
import SwiftUI

/// One sensory attribute on the −2…+2 scale: its name and current label,
/// then five stops to tap. Tapping the chosen stop again clears the rating,
/// so "not evaluated" is always one tap away. VoiceOver adjusts it with a
/// swipe.
struct RatingRow: View {
    let attribute: SensoryAttribute
    @Binding var value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(attribute.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(CupRating.label(value))
                    .font(.footnote)
                    .foregroundStyle(value == nil ? Theme.text3 : value == 0 ? Theme.ready : Theme.accent)
            }
            HStack(spacing: 4) {
                ForEach(Array(CupRating.range), id: \.self) { stop in
                    Button {
                        value = value == stop ? nil : stop
                    } label: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(fill(stop))
                            .overlay {
                                if stop == 0 { Capsule().fill(Theme.text3).frame(width: 2, height: 14) }
                            }
                            .frame(height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(attribute.name)
        .accessibilityValue(CupRating.label(value))
        .accessibilityHint("Swipe up for too much, down for too little. Double-tap to clear.")
        .accessibilityAction { value = nil }
        .accessibilityAdjustableAction { direction in
            let current = value ?? 0
            switch direction {
            case .increment: value = value == nil ? 0 : min(2, current + 1)
            case .decrement: value = value == nil ? 0 : max(-2, current - 1)
            @unknown default: break
            }
        }
    }

    /// The chosen stop and the stops between it and "ideal" are filled, so
    /// the row reads as a bar out from the centre.
    private func fill(_ stop: Int) -> Color {
        guard let value else { return Theme.raised }
        if value == 0 { return stop == 0 ? Theme.ready : Theme.raised }
        let between = value < 0 ? (value...0).contains(stop) && stop != 0 : (0...value).contains(stop) && stop != 0
        return between ? Theme.accent.opacity(stop == value ? 1 : 0.55) : Theme.raised
    }
}

/// A row of chips for an optional choice; tapping the chosen one clears it.
struct ChoiceRow<Choice: Hashable>: View {
    let title: String
    let choices: [Choice]
    let name: (Choice) -> String
    @Binding var selection: Choice?

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).frame(minWidth: 84, alignment: .leading)
            ForEach(choices, id: \.self) { choice in
                let chosen = selection == choice
                Button {
                    selection = chosen ? nil : choice
                } label: {
                    Text(name(choice))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(chosen ? Theme.ground : Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(chosen ? Theme.accent : Theme.raised, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title): \(name(choice))")
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}

extension Verdict {
    var name: String { rawValue.capitalized }
}

extension Drawdown {
    var name: String { rawValue.capitalized }
}

extension Agitation {
    var name: String { rawValue.capitalized }
}
