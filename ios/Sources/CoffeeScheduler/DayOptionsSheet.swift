import CoffeeCore
import SwiftUI

/// Identifies the day whose options are showing.
struct DayRoute: Identifiable, Hashable {
    let date: String
    var id: String { date }
}

/// Options for one schedule day, opened by tapping its date: skip the day, or drink a different
/// amount that day.
struct DayOptionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let date: String

    // Pre-filled with the day's override, or the current defaults
    @State private var dailyGrams: Double?
    @State private var doseSizeGrams: Double?
    @State private var error: String?

    var body: some View {
        // Read from the model so the toggle follows the saved state
        let isSkip = model.schedule.first { $0.date == date }?.isSkip ?? false
        let range = model.skipRanges.first { $0.startDate <= date && date <= $0.endDate }
        Form {
            Group {
                Section {
                    Toggle(
                        "Skip this day",
                        isOn: Binding(
                            get: { isSkip },
                            set: { _ in model.toggleSkipDay(date) }
                        ))
                } footer: {
                    if isSkip, let range, range.startDate != range.endDate {
                        Text(
                            "Part of a skip from \(Format.shortDay(range.startDate)) to \(Format.shortDay(range.endDate)). Turning it off here un-skips just this day."
                        )
                    } else {
                        Text("For days away from home: no coffee is planned that day, so the bags after it are pushed back a day.")
                    }
                }

                let existing = model.consumptionOverride(on: date)
                Section {
                    LabeledContent("Total for the day") {
                        gramsField($dailyGrams)
                    }
                    LabeledContent("Dose size") {
                        gramsField($doseSizeGrams)
                    }
                    Button(existing == nil ? "Set override" : "Update override", action: saveOverride)
                    if let existing {
                        Button("Clear override", role: .destructive) {
                            model.deleteConsumptionOverride(id: existing.id)
                            dismiss()
                        }
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.gapText)
                    }
                } header: {
                    Text("Drink more or less")
                } footer: {
                    Text(
                        existing == nil
                            ? "Usually \(Format.grams(model.settings.dailyConsumptionGrams)) g a day in \(Format.grams(Scheduler.doseSizeGrams)) g doses."
                            : "This day has an override; the usual is \(Format.grams(model.settings.dailyConsumptionGrams)) g a day.")
                }
            }
            .listRowBackground(Theme.card)
            .listRowSeparatorTint(Theme.hairline)
        }
        .themedList()
        .onAppear {
            let existing = model.consumptionOverride(on: date)
            dailyGrams = existing?.dailyGrams ?? model.settings.dailyConsumptionGrams
            doseSizeGrams = existing?.doseSizeGrams ?? Scheduler.doseSizeGrams
        }
        .navigationTitle(Format.longDay(date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func gramsField(_ value: Binding<Double?>) -> some View {
        HStack(spacing: 4) {
            TextField("Grams", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text("g").foregroundStyle(.secondary)
        }
    }

    private func saveOverride() {
        error = model.setConsumptionOverride(date: date, dailyGrams: dailyGrams ?? 0, doseSizeGrams: doseSizeGrams ?? 0)
        if error == nil { dismiss() }
    }
}
