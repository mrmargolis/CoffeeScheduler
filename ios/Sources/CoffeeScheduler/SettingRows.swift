import SwiftUI

/// A settings row: a title, with an optional roaster dot and second line,
/// and a control at the far edge.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    var dot: Color?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            if let dot {
                Circle().fill(dot).frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.text2).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .frame(minHeight: 48)
    }
}

/// Minus and plus around a value, in one rounded well.
struct StepperWell: View {
    let text: String
    /// What it changes, for VoiceOver: "rest days".
    let subject: String
    let value: Binding<Int>
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack(spacing: 0) {
            button("minus", label: "Less \(subject)", change: -step)
            Text(text).font(.callout.bold()).monospacedDigit().frame(minWidth: 48)
            button("plus", label: "More \(subject)", change: step)
        }
        .background(Theme.raised, in: Capsule())
    }

    private func button(_ icon: String, label: String, change: Int) -> some View {
        let next = value.wrappedValue + change
        return Button {
            value.wrappedValue = next
        } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // Plain, so each end takes its own taps inside the list row
        .buttonStyle(.plain)
        .disabled(!range.contains(next))
        .accessibilityLabel(label)
    }
}

/// A row that goes somewhere: an icon tile, two lines and a chevron.
struct IconRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(Theme.text2).lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.text3)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

/// The small print under a section.
struct SectionFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.text3)
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
    }
}
