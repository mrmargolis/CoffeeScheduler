import CoffeeCore
import SwiftUI

/// A field of the bag being added, its name on the left and what's in it,
/// editable, on the right.
struct BagTextRow: View {
    let title: String
    @Binding var text: String
    var prompt = "Not found"

    var body: some View {
        SettingRow(title: title) {
            TextField(title, text: $text, prompt: Text(prompt).foregroundStyle(Theme.text3), axis: .vertical)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.text2)
                .lineLimit(1...3)
        }
    }
}

/// The roast date: a date picker once there is one, a button to set one
/// until then, and a button to clear it.
struct RoastDateRow: View {
    /// `YYYY-MM-DD`.
    @Binding var date: String?

    var body: some View {
        SettingRow(title: "Roasted") {
            if let iso = date {
                HStack(spacing: 4) {
                    DatePicker("Roasted", selection: binding(iso), in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                    Button("Clear the roast date", systemImage: "xmark.circle.fill") { date = nil }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.text3)
                        .buttonStyle(.borderless)
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

    var body: some View {
        SettingRow(title: "Weight") {
            HStack(spacing: 4) {
                TextField("Weight", text: text, prompt: Text("Not found").foregroundStyle(Theme.text3))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.text2)
                Text("g").foregroundStyle(Theme.text3)
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
