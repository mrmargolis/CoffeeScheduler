import CoffeeCore
import SwiftUI

/// Which brew methods get dial-in advice, listed from the imported brews.
struct DialInSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var methods: [DialInMethod] = []
    @State private var grinders: [GrinderSetting] = []
    @State private var temperatureStep = CoffeeStore.defaultTemperatureStep
    @State private var error: String?

    var body: some View {
        List {
            Section {
                if methods.isEmpty {
                    Text("Import a BeanConqueror export to list your brew methods.").foregroundStyle(Theme.text2)
                }
                ForEach(methods, id: \.name) { method in
                    Toggle(isOn: Binding(get: { method.isOn }, set: { set(method.name, on: $0) })) {
                        Text(method.name).font(.callout.weight(.semibold))
                    }
                    .tint(Theme.accent)
                    .frame(minHeight: 44)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.gapText)
                }
            } header: {
                SectionLabel(title: "Brew methods").listRowInsets(Theme.labelInsets)
            } footer: {
                SectionFooter(
                    text: """
                        Dial-in advice is tuned for pour-over. A bag brewed only with methods turned off \
                        here doesn't offer it. V60, Hario Switch, Hario Alpha and Orea are on unless you turn them off.
                        """)
            }
            .listRowBackground(Theme.card)
            .listRowSeparatorTint(Theme.hairline)

            Group {
                grindersSection
                temperatureSection
                notesReaderSection
            }
            .listRowBackground(Theme.card)
            .listRowSeparatorTint(Theme.hairline)
        }
        .themedList()
        .navigationTitle("Dial-in")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private var grindersSection: some View {
        Section {
            if grinders.isEmpty {
                Text("Import a BeanConqueror export to list your grinders.").foregroundStyle(Theme.text2)
            }
            ForEach(grinders, id: \.name) { grinder in
                NavigationLink {
                    GrinderForm(grinder: grinder)
                } label: {
                    SettingRow(title: grinder.name, subtitle: GrinderForm.summary(grinder)) { EmptyView() }
                }
            }
        } header: {
            SectionLabel(title: "Grinders").listRowInsets(Theme.labelInsets)
        } footer: {
            SectionFooter(
                text: """
                    A grind suggestion moves by the grinder's step. It starts as the change you make most often \
                    between brews of a bag. Outside the grinder's usual range, suggestions give a direction instead.
                    """)
        }
    }

    private var notesReaderSection: some View {
        Section {
            NavigationLink {
                NotesReaderCheckView()
            } label: {
                SettingRow(title: "Check the notes reader", subtitle: NotesModelReader.isEnabled ? "On" : "Off") {
                    EmptyView()
                }
            }
        } header: {
            SectionLabel(title: "Notes reader").listRowInsets(Theme.labelInsets)
        } footer: {
            SectionFooter(
                text: """
                    Reads the notes on the evaluation sheet and suggests character tags and flavours, marked until \
                    you keep them. The check runs it over your newest brew notes.
                    """)
        }
    }

    private var temperatureSection: some View {
        Section {
            SettingRow(title: "Temperature step") {
                StepperWell(
                    text: "\(Format.grams(temperatureStep)) °C", subject: "temperature step",
                    value: Binding(
                        get: { Int(temperatureStep) },
                        set: {
                            error = model.setTemperatureStep(Double($0))
                            temperatureStep = model.temperatureStep()
                        }),
                    range: 1...5)
            }
        }
    }

    private func reload() {
        methods = model.dialInMethods()
        grinders = model.grinderSettings()
        temperatureStep = model.temperatureStep()
    }

    private func set(_ name: String, on: Bool) {
        error = model.setDialIn(method: name, on: on)
        methods = model.dialInMethods()
    }
}
