import CoffeeCore
import SwiftUI

/// The bag being added: where it was filled in from, every field editable,
/// and, pinned at the bottom, the ways to fill it in and the button that
/// hands it to BeanConqueror. Next steps through the fields; the bar hides
/// while typing.
struct BagDraftForm: View {
    @Bindable var intake: BagIntake
    let actions: BagDockActions
    @FocusState private var focus: BagField?
    @State private var originOpen: Bool
    @State private var labelPick: LabelPick?

    init(intake: BagIntake, actions: BagDockActions, originOpen: Bool = false) {
        self.intake = intake
        self.actions = actions
        _originOpen = State(initialValue: originOpen)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Group {
                    BagSourcesSection(
                        intake: intake,
                        onPickText: { labelPick = LabelPick(photo: $0.id, target: nil) },
                        onCheckGuesses: { checkGuesses(proxy) },
                        onTakePhoto: actions.takePhoto)
                    bagSection
                    originSection
                }
                .listRowBackground(Theme.card)
                .listRowSeparatorTint(Theme.hairline)
            }
            .themedList()
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focus == nil { BagDock(intake: intake, actions: actions) }
            }
            .toolbar { keyboardBar }
            .onChange(of: focus) { _, field in
                guard let field else { return }
                withAnimation { proxy.scrollTo(field, anchor: .center) }
            }
            .sheet(item: $labelPick) { pick in
                BagLabelSheet(photos: intake.photos, pick: pick) { line, field in intake.type(line, in: field) }
            }
        }
    }

    private var bagSection: some View {
        Section {
            row(.coffee)
            row(.roaster)
            BagDateWeightRows(intake: intake, focus: $focus)
        } header: {
            SectionLabel(title: "Bag").listRowInsets(Theme.labelInsets)
        }
    }

    private var originSection: some View {
        Section {
            Button {
                withAnimation { originOpen.toggle() }
            } label: {
                OriginHeader(draft: intake.draft, isOpen: originOpen)
            }
            .accessibilityHint(originOpen ? "Hides these fields" : "Shows these fields")
            if originOpen {
                ForEach(BagField.origin, id: \.self) { field in
                    if field == .url {
                        BagTextRow(
                            field: field, intake: intake, focus: $focus, onReturn: { move(1) },
                            accessory: {
                                Button("Find page", systemImage: "magnifyingglass") { actions.search(.google) }
                                    .font(.footnote.weight(.semibold))
                                    .buttonStyle(.borderless)
                            })
                    } else {
                        row(field)
                    }
                }
            }
        } header: {
            SectionLabel(title: "Notes and origin").listRowInsets(Theme.labelInsets)
        }
    }

    private func row(_ field: BagField) -> some View {
        BagTextRow(field: field, intake: intake, focus: $focus, onReturn: { move(1) }, accessory: { EmptyView() })
    }

    @ToolbarContentBuilder private var keyboardBar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Button("Previous field", systemImage: "chevron.up") { move(-1) }
                .disabled(focus == BagField.typed.first)
            Button("Next field", systemImage: "chevron.down") { move(1) }
                .disabled(focus == BagField.typed.last)
            Spacer()
            if let photo = intake.photos.last, let field = focus, field.text != nil {
                Button("Label text", systemImage: "text.viewfinder") { labelPick = LabelPick(photo: photo.id, target: field) }
                    .labelStyle(.titleAndIcon)
            }
            Button("Done") { focus = nil }.fontWeight(.semibold)
        }
    }

    /// Focus the next field, or the one before, opening "Notes and origin"
    /// to reach one of its fields.
    private func move(_ step: Int) {
        let fields = BagField.typed
        guard let focus, let index = fields.firstIndex(of: focus), fields.indices.contains(index + step) else {
            self.focus = nil
            return
        }
        go(to: fields[index + step])
    }

    /// Each tap goes to the next guess after the field being typed in.
    private func checkGuesses(_ proxy: ScrollViewProxy) {
        let guesses = BagField.allCases.filter(intake.draft.isGuess)
        let order = BagField.allCases
        let after = focus.flatMap { current in
            guesses.first { (order.firstIndex(of: $0) ?? 0) > (order.firstIndex(of: current) ?? 0) }
        }
        guard let next = after ?? guesses.first else { return }
        if next == .roastDate {
            withAnimation { proxy.scrollTo(next, anchor: .center) }
        } else {
            go(to: next)
        }
    }

    private func go(to field: BagField) {
        if BagField.origin.contains(field) && !originOpen {
            originOpen = true
            // The row has to be there before it can take focus
            Task { focus = field }
        } else {
            focus = field
        }
    }
}

/// "Notes and origin" folded to a line, or how much of it is filled in.
private struct OriginHeader: View {
    let draft: BagDraft
    let isOpen: Bool

    var body: some View {
        let (filled, guesses) = draft.count(BagField.origin)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                if isOpen {
                    Text("Hide").foregroundStyle(Theme.text2)
                } else if filled == 0 {
                    Text("Tasting notes, country, region, producer, variety, process and link")
                        .foregroundStyle(Theme.text3)
                } else {
                    if !draft.originLine.isEmpty { Text(draft.originLine).foregroundStyle(Theme.text) }
                    if draft.has(.notes) { Text(draft.notes).foregroundStyle(Theme.text3) }
                }
            }
            .font(.subheadline)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Text("\(filled) of \(BagField.origin.count)")
                if guesses > 0 { Text("· \(guesses) \(guesses == 1 ? "guess" : "guesses")").foregroundStyle(Theme.accent) }
                Image(systemName: isOpen ? "chevron.up" : "chevron.down").imageScale(.small)
            }
            .font(.caption)
            .foregroundStyle(Theme.text3)
        }
        .padding(.vertical, 6)
    }
}
