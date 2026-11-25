import CoffeeCore
import SwiftUI

/// Rate a cup: the verdict, the six attributes and the drawdown fit on one
/// screen; the recipe, prefilled from the bag's latest evaluation or brew,
/// is folded into one line and opened only to change it.
struct CupEvaluationForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    @State private var evaluation: CupEvaluation
    @State private var editsRecipe = false
    @State private var editsTags = false
    @State private var usedFlavours: [String] = []
    /// The bag's brews around this cup, to link it to; only when editing.
    @State private var brews: [LoggedBrew] = []
    /// Set once a new cup is saved, to show what to try next.
    @State private var advice: DialInAdvice?
    @State private var decided: SavedExperiment?
    @State private var stillOpen: SavedExperiment?
    @State private var confirmingDelete = false
    @State private var error: String?

    init(evaluation: CupEvaluation, isNew: Bool, editsRecipe: Bool = false, editsTags: Bool = false) {
        self.isNew = isNew
        _evaluation = State(initialValue: evaluation)
        _editsRecipe = State(initialValue: editsRecipe)
        _editsTags = State(initialValue: editsTags)
    }

    var body: some View {
        ScrollView {
            if let advice {
                DialInAdviceView(evaluation: evaluation, advice: advice, decided: decided, stillOpen: stillOpen)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            } else {
                fields
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .selectsNumbersOnTap()
        .background(Theme.ground)
        .foregroundStyle(Theme.text)
        .navigationTitle(advice != nil ? "Next cup" : isNew ? "Evaluate a cup" : "Edit evaluation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if advice != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            } else {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .task {
            usedFlavours = model.usedFlavours()
            if !isNew { brews = nearbyBrews() }
        }
        .confirmationDialog("Delete this evaluation?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Compared with the last cup").font(.caption).foregroundStyle(Theme.text3)
                ChoiceRow(title: "", choices: Verdict.allCases, name: \.name, selection: $evaluation.verdict)
            }
            ratings
            ChoiceRow(title: "Drawdown", choices: Drawdown.allCases, name: \.name, selection: $evaluation.drawdown)
            Toggle("Stalled or channelled", isOn: $evaluation.flowProblem)
                .font(.subheadline)
                .tint(Theme.accent)
            RecipeEditor(recipe: $evaluation.recipe, isExpanded: $editsRecipe)
            if !isNew { BrewLinkCard(evaluation: $evaluation, brews: brews) }
            TagsEditor(
                evaluation: $evaluation, usedFlavours: usedFlavours, isExpanded: $editsTags, reader: NotesModelReader.forSheet)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.gapText)
            }
            if !isNew {
                Button("Delete evaluation", role: .destructive) { confirmingDelete = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var ratings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Too little")
                Spacer()
                Text("Ideal")
                Spacer()
                Text("Too much")
            }
            .font(.caption)
            .foregroundStyle(Theme.text3)
            .accessibilityHidden(true)
            ForEach(SensoryAttribute.allCases, id: \.self) { attribute in
                RatingRow(attribute: attribute, value: $evaluation.ratings[attribute])
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.tileRadius))
    }

    /// A new cup decides the open experiment, then shows its advice; an
    /// edited one just closes. Deciding comes first: saving a cup marked
    /// dialed in closes whatever is still open.
    private func save() {
        if isNew { decided = model.decideExperiment(with: evaluation) }
        error = model.saveEvaluation(evaluation)
        guard error == nil else { return }
        if isNew {
            stillOpen = model.experiments(forBean: evaluation.beanID).first { $0.status == .open }
            withAnimation(.snappy) { advice = model.advice(for: evaluation) }
        } else {
            dismiss()
        }
    }

    /// Brews around the cup's time, and the one it's linked to wherever it is.
    private func nearbyBrews() -> [LoggedBrew] {
        let near = model.brews(near: evaluation)
        guard let linked = model.linkedBrew(for: evaluation), !near.contains(linked) else { return near }
        return (near + [linked]).sorted { $0.timestamp > $1.timestamp }
    }

    private func delete() {
        error = model.deleteEvaluation(id: evaluation.id)
        if error == nil { dismiss() }
    }
}

/// The cup's recipe: one summary line that opens into fields.
private struct RecipeEditor: View {
    @Binding var recipe: CupRecipe
    @Binding var isExpanded: Bool

    var body: some View {
        FoldedCard(title: "Recipe", summary: summary, isExpanded: $isExpanded) { fields }
    }

    private var summary: String {
        let parts = recipe.brew.summaryParts + [recipe.agitation.map { "\($0.name) agitation" }].compactMap { $0 }
        return parts.isEmpty ? "Not recorded" : parts.joined(separator: " · ")
    }

    private var fields: some View {
        VStack(spacing: 10) {
            textField("Grinder", text: $recipe.brew.grinder)
            textField("Grind", text: $recipe.brew.grindSetting)
            numberField("Temperature °C", value: $recipe.brew.temperatureC)
            numberField("Dose g", value: $recipe.brew.doseGrams)
            numberField("Water g", value: $recipe.brew.waterGrams)
            ChoiceRow(title: "Agitation", choices: Agitation.allCases, name: \.name, selection: $recipe.agitation)
            textField("Method", text: $recipe.brew.method)
            textField("Water recipe", text: $recipe.brew.water)
            textField("Profile", text: $recipe.brew.profile)
        }
        .font(.subheadline)
        .padding(.bottom, 8)
    }

    private func textField(_ title: String, text: Binding<String?>) -> some View {
        LabeledContent(title) {
            TextField(title, text: Binding(get: { text.wrappedValue ?? "" }, set: { text.wrappedValue = Self.clean($0) }))
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 36)
    }

    private func numberField(_ title: String, value: Binding<Double?>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number).numberEntry()
        }
        .frame(minHeight: 36)
    }

    /// Blank is unknown. Spaces are kept while typing; the store trims them.
    private static func clean(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
