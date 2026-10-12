import CoffeeCore
import SwiftUI

/// Edit a bag's rest days, roast date, planned thaw and freeze-after grams.
/// The roast
/// date is offered only when BeanConqueror didn't supply one, the planned thaw
/// only for a frozen bag, and freeze-after only for one that isn't frozen.
struct BeanSettingsForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let bean: Bean

    @State private var restDays: Int?
    @State private var setsRoastDate: Bool
    @State private var roastDate: Date
    @State private var hasPlannedThaw: Bool
    @State private var plannedThaw: Date
    @State private var freezeAfterGrams: Double?
    @State private var error: String?

    init(bean: Bean, today: String) {
        self.bean = bean
        _restDays = State(initialValue: bean.restDays)
        _setsRoastDate = State(initialValue: false)
        _roastDate = State(initialValue: Format.date(today))
        _hasPlannedThaw = State(initialValue: bean.plannedThawDate != nil)
        _plannedThaw = State(initialValue: Format.date(bean.plannedThawDate ?? DateUtils.addDays(today, 7)))
        _freezeAfterGrams = State(initialValue: bean.freezeAfterGrams)
    }

    var body: some View {
        Form {
            Group {
                Section {
                    LabeledContent("Rest days") {
                        TextField(
                            "Rest days",
                            value: $restDays,
                            format: .number,
                            prompt: Text("\(bean.effectiveRestDays), inherited")
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Leave empty to use the roaster's default, or the default in Settings.")
                }

                if bean.roastDate == nil {
                    Section {
                        Toggle("Set roast date", isOn: $setsRoastDate)
                        if setsRoastDate {
                            DatePicker("Roast date", selection: $roastDate, displayedComponents: .date)
                        }
                    } footer: {
                        Text("BeanConqueror didn't include one. Without it the bag has no ready date and isn't scheduled.")
                    }
                }

                if bean.isFrozen {
                    Section {
                        Toggle("Planned thaw", isOn: $hasPlannedThaw)
                        if hasPlannedThaw {
                            DatePicker("Thaw on", selection: $plannedThaw, displayedComponents: .date)
                        }
                    } footer: {
                        Text("The bag comes out of the freezer on this day and is scheduled from then. Without a date it stays out of the schedule.")
                    }
                } else {
                    Section {
                        LabeledContent("Freeze after") {
                            HStack(spacing: 4) {
                                TextField("Grams", value: $freezeAfterGrams, format: .number, prompt: Text("e.g. 125"))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                Text("g used").foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text(
                            "Freeze the rest of the bag automatically once this much has been brewed. The bag is \(Format.grams(bean.weightGrams)) g."
                        )
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.gapText)
                    }
                }
            }
            .listRowBackground(Theme.card)
            .listRowSeparatorTint(Theme.hairline)
        }
        .themedList()
        // Dates are calendar days; pick them in UTC so they can't shift.
        .environment(\.timeZone, Format.utc)
        .navigationTitle("Edit bag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
    }

    /// Every field is saved; ones not shown keep their value.
    private var settings: BeanSettings {
        BeanSettings(
            restDays: restDays,
            roastDate: bean.roastDate ?? (setsRoastDate ? Format.iso(roastDate) : nil),
            plannedThawDate: bean.isFrozen ? (hasPlannedThaw ? Format.iso(plannedThaw) : nil) : bean.plannedThawDate,
            freezeAfterGrams: bean.isFrozen ? bean.freezeAfterGrams : freezeAfterGrams
        )
    }

    private func save() {
        error = model.updateBeanSettings(id: bean.id, settings)
        if error == nil { dismiss() }
    }
}
