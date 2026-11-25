import CoffeeCore
import SwiftUI

/// One grinder's step and direction, with what its brews say about it.
struct GrinderForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let grinder: GrinderSetting
    @State private var step: Double?
    @State private var higherIsCoarser: Bool
    @State private var error: String?

    init(grinder: GrinderSetting) {
        self.grinder = grinder
        _step = State(initialValue: grinder.step)
        _higherIsCoarser = State(initialValue: grinder.higherIsCoarser)
    }

    var body: some View {
        Form {
            Group {
                Section {
                    LabeledContent("Step") {
                        TextField(
                            "Step", value: $step, format: .number,
                            prompt: Text(grinder.history.usualStep.map { "\(Self.number($0)), usual" } ?? "Not known")
                        )
                        .numberEntry()
                    }
                    Toggle("Higher is coarser", isOn: $higherIsCoarser).tint(Theme.accent)
                } footer: {
                    SectionFooter(text: Self.historyNote(grinder))
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.gapText)
                    }
                }
            }
            .listRowBackground(Theme.card)
            .listRowSeparatorTint(Theme.hairline)
        }
        .themedList()
        .selectsNumbersOnTap()
        .navigationTitle(grinder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    error = model.setGrinder(grinder.name, step: step, higherIsCoarser: higherIsCoarser)
                    if error == nil { dismiss() }
                }
            }
        }
    }

    /// "Step 0.1 · higher is coarser · usually 1.3–1.75"
    static func summary(_ grinder: GrinderSetting) -> String {
        var parts = [grinder.effectiveStep.map { "Step \(number($0))" } ?? "No step yet"]
        parts.append(grinder.higherIsCoarser ? "higher is coarser" : "lower is coarser")
        if let range = grinder.history.usualRange {
            parts.append("usually \(number(range.lowerBound))–\(number(range.upperBound))")
        }
        return parts.joined(separator: " · ")
    }

    private static func historyNote(_ grinder: GrinderSetting) -> String {
        let step = grinder.history.usualStep.map { "You usually change it by \(number($0)) between brews of a bag. " } ?? ""
        let range =
            grinder.history.usualRange.map {
                "Most brews are between \(number($0.lowerBound)) and \(number($0.upperBound)); outside that, suggestions give a direction only."
            } ?? "There aren't enough brews yet to know its usual range."
        return step + range + " Leave the step empty to use the usual one."
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
