import CoffeeCore
import SwiftUI

/// A row of the bag being added: the field's name, marked when its value
/// is a guess, and the control for it.
struct BagFieldRow<Control: View>: View {
    let title: String
    let isGuess: Bool
    @ViewBuilder let control: Control

    var body: some View {
        SettingRow(title: title, subtitle: isGuess ? "Guess" : nil, subtitleColor: Theme.accent) {
            control
        }
    }
}

/// A field of the bag being added, its name on the left and what's in it,
/// editable, on the right.
struct BagTextRow: View {
    let title: String
    @Binding var text: String
    var isGuess = false
    var prompt = "Not found"

    var body: some View {
        BagFieldRow(title: title, isGuess: isGuess) {
            HStack(spacing: 4) {
                TextField(title, text: $text, prompt: Text(prompt).foregroundStyle(Theme.text3), axis: .vertical)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1...3)
                if !text.isEmpty {
                    ClearButton(title: title) { text = "" }
                }
            }
        }
    }
}

/// The roast date: a date picker once there is one, a button to set one
/// until then, and a button to clear it.
struct RoastDateRow: View {
    /// `YYYY-MM-DD`.
    @Binding var date: String?
    var isGuess = false

    var body: some View {
        BagFieldRow(title: "Roasted", isGuess: isGuess) {
            if let iso = date {
                HStack(spacing: 4) {
                    DatePicker("Roasted", selection: binding(iso), in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                    ClearButton(title: "the roast date") { date = nil }
                }
            } else {
                Button("Add date") { date = DateUtils.today() }
                    .buttonStyle(.borderless)
            }
        }
    }

    /// The picker's date: the ISO day's start where the phone is.
    private func binding(_ iso: String) -> Binding<Date> {
        Binding {
            let parts = iso.split(separator: "-").compactMap { Int($0) }
            let components = DateComponents(year: parts.first, month: parts.dropFirst().first, day: parts.last)
            return Calendar.current.date(from: components) ?? Date()
        } set: { picked in
            date = DateUtils.isoString(picked)
        }
    }
}

/// The weight in whole grams, as BeanConqueror keeps it.
struct WeightRow: View {
    @Binding var grams: Int?
    var isGuess = false

    var body: some View {
        BagFieldRow(title: "Weight", isGuess: isGuess) {
            HStack(spacing: 4) {
                TextField("Weight", text: text, prompt: Text("Not found").foregroundStyle(Theme.text3))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.text2)
                Text("g").foregroundStyle(Theme.text3)
                if grams != nil {
                    ClearButton(title: "Weight") { grams = nil }
                }
            }
        }
    }

    private var text: Binding<String> {
        Binding {
            grams.map(String.init) ?? ""
        } set: { typed in
            grams = Int(typed.filter(\.isNumber))
        }
    }
}

/// A field's button that empties it.
private struct ClearButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button("Clear \(title)", systemImage: "xmark.circle.fill", action: action)
            .labelStyle(.iconOnly)
            .foregroundStyle(Theme.text3)
            .buttonStyle(.borderless)
    }
}
