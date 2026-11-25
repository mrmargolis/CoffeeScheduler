import CoffeeCore
import SwiftUI

/// Choose one change for the next cup instead of the suggestion: what to
/// change, which way, and optionally the value to try.
struct OwnExperimentEditor: View {
    let cup: CupEvaluation
    let grinder: GrinderSetting?
    let save: (DialInExperiment) -> Void
    @State private var variable: DialInVariable? = .grind
    @State private var direction: DialInDirection? = .down
    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Your change")
            ChoiceRow(title: "", choices: DialInVariable.allCases, name: \.name, selection: $variable)
            if let variable {
                ChoiceRow(title: "", choices: [DialInDirection.up, .down], name: { DialInMove(variable, $0).name }, selection: $direction)
            }
            TextField("Value to try (optional)", text: $value)
                .keyboardType(.decimalPad)
                .font(.subheadline)
                .padding(10)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
            Button("Save for the next cup") {
                guard let variable, let direction else { return }
                save(DialInExperiment.custom(DialInMove(variable, direction), to: value, after: cup, grinder: grinder))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(Theme.ground)
            .disabled(variable == nil || direction == nil)
        }
        .cardBackground(Theme.card)
    }
}

extension DialInVariable {
    var name: String { rawValue.capitalized }
}
