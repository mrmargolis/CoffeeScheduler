import CoffeeCore
import SwiftUI

/// The width of a rating row's name column, shared with the scale's header.
let ratingNameWidth: CGFloat = 116

/// One sensory attribute on the −2…+2 scale in a single row: its name and
/// current label on the left, five stops to tap on the right. Tapping the
/// chosen stop again clears the rating, so "not rated" is always one tap
/// away. VoiceOver adjusts it with a swipe.
struct RatingRow: View {
    let attribute: SensoryAttribute
    @Binding var value: Int?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(attribute.shortName).font(.subheadline.weight(.semibold))
                Text(CupRating.label(value))
                    .font(.caption)
                    .foregroundStyle(value == nil ? Theme.text3 : value == 0 ? Theme.ready : Theme.accent)
            }
            .frame(width: ratingNameWidth, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(Array(CupRating.range), id: \.self) { stop in
                    Button {
                        value = value == stop ? nil : stop
                    } label: {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(fill(stop))
                            .overlay {
                                if stop == 0 && value != 0 { Capsule().fill(Theme.text3).frame(width: 2, height: 12) }
                            }
                            .frame(height: 30)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(attribute.name)
        .accessibilityValue(CupRating.label(value))
        .accessibilityIdentifier("rating-\(attribute.rawValue)")
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

/// A titled segmented control for an optional choice; tapping the chosen
/// segment clears it.
struct SegmentedChoice<Choice: Hashable>: View {
    let title: String
    var note: String?
    let choices: [Choice]
    /// Short enough for a third of half the screen.
    let label: (Choice) -> String
    /// The full name, for VoiceOver.
    let name: (Choice) -> String
    @Binding var selection: Choice?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text(title).foregroundStyle(Theme.text2) + Text(note.map { " · \($0)" } ?? "").fontWeight(.regular).foregroundStyle(Theme.text3))
                .font(.footnote.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 2) {
                ForEach(choices, id: \.self) { choice in
                    let chosen = selection == choice
                    Button {
                        selection = chosen ? nil : choice
                    } label: {
                        Text(label(choice))
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(chosen ? Theme.ground : Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(chosen ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title): \(name(choice))")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// A tag to tap on or off.
struct Chip: View {
    let text: String
    let isOn: Bool
    /// Share the row's width with the other chips.
    var fills = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isOn ? Theme.ground : Theme.text)
                .padding(.horizontal, 14)
                .frame(maxWidth: fills ? .infinity : nil, minHeight: 36)
                .background(isOn ? Theme.accent : Theme.raised, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension SensoryAttribute {
    /// The name in a rating row: "Intensity", "Finish".
    var shortName: String {
        switch self {
        case .intensity: "Intensity"
        case .finish: "Finish"
        default: name
        }
    }
}

extension Drawdown {
    var name: String { rawValue.capitalized }
}

extension Agitation {
    var name: String { rawValue.capitalized }
    /// "Med" fits a third of half the screen.
    var shortName: String { self == .medium ? "Med" : name }
}

extension DialInVariable {
    /// "Temp" fits a quarter of the screen.
    var shortName: String { self == .temperature ? "Temp" : name }
}
