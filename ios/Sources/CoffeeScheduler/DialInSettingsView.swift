import CoffeeCore
import SwiftUI

/// Which brew methods get dial-in advice, listed from the imported brews.
struct DialInSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var methods: [DialInMethod] = []
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
        }
        .themedList()
        .navigationTitle("Dial-in")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { methods = model.dialInMethods() }
    }

    private func set(_ name: String, on: Bool) {
        error = model.setDialIn(method: name, on: on)
        methods = model.dialInMethods()
    }
}
