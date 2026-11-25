import CoffeeCore
import SwiftUI

/// A card on the evaluation sheet that shows one summary line and opens
/// into its fields.
struct FoldedCard<Fields: View>: View {
    let title: String
    let summary: String
    @Binding var isExpanded: Bool
    @ViewBuilder let fields: () -> Fields

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Text(summary).font(.footnote).foregroundStyle(Theme.text2).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(Theme.text3)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the fields" : "Shows the fields to change")

            if isExpanded { fields().padding(.top, 6) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.tileRadius))
    }
}

/// Character tags, flavours and notes: optional, folded away until wanted.
/// With a notes reader, the notes are read a moment after typing stops, and
/// what it finds is proposed: marked until kept, and one tap to remove.
struct TagsEditor: View {
    @Binding var evaluation: CupEvaluation
    let usedFlavours: [String]
    @Binding var isExpanded: Bool
    var reader: (any NotesReader)?
    @State private var newFlavour = ""
    @State private var proposedFlavours: [String] = []
    /// Proposals removed, and tags turned off, not to propose again.
    @State private var rejected: Set<CharacterTag> = []
    @State private var rejectedFlavours: Set<String> = []
    /// The notes as last read, or as they were when the sheet opened.
    @State private var readNotes: String??

    var body: some View {
        FoldedCard(title: "Tags & notes", summary: summary, isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                characterChips
                flavours
                TextField("Notes", text: notes, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.subheadline)
                    .padding(10)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
                if hasProposals {
                    Label("Suggested from your notes: tap to keep, × to remove.", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Theme.text2)
                }
            }
            .padding(.bottom, 8)
        }
        .task(id: evaluation.notes) { await read() }
    }

    private var hasProposals: Bool {
        !proposedFlavours.isEmpty || evaluation.character.values.contains(.model)
    }

    /// Read the notes once typing has paused, if they changed since the
    /// sheet opened or they were last read.
    private func read() async {
        guard let reader else { return }
        guard let last = readNotes else {
            readNotes = .some(evaluation.notes)
            return
        }
        guard last != evaluation.notes, let notes = evaluation.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty
        else { return }
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled, let reading = await reader.read(notes), !Task.isCancelled else { return }
        readNotes = .some(evaluation.notes)
        proposedFlavours = evaluation.takeProposals(reading, rejected: rejected, rejectedFlavours: rejectedFlavours)
    }

    private var summary: String {
        let tags = CharacterTag.allCases.filter { evaluation.character[$0] != nil }.map(\.name) + evaluation.flavours
        var parts = tags.isEmpty ? [] : [tags.joined(separator: ", ")]
        if let notes = evaluation.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("notes") }
        return parts.isEmpty ? "None" : parts.joined(separator: " · ")
    }

    private var characterChips: some View {
        HStack(spacing: 8) {
            ForEach(CharacterTag.allCases, id: \.self) { tag in
                if evaluation.character[tag] == .model {
                    ProposedChip(text: tag.name) {
                        evaluation.accept(tag)
                    } remove: {
                        evaluation.character[tag] = nil
                        rejected.insert(tag)
                    }
                } else {
                    let on = evaluation.character[tag] != nil
                    Chip(text: tag.name, isOn: on) {
                        evaluation.character[tag] = on ? nil : .user
                        if on { rejected.insert(tag) }
                    }
                }
            }
        }
    }

    private var flavours: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(evaluation.flavours, id: \.self) { flavour in
                    Chip(text: flavour, isOn: true, removes: true) {
                        evaluation.flavours.removeAll { $0 == flavour }
                        rejectedFlavours.insert(flavour.lowercased())
                    }
                }
                ForEach(proposedFlavours, id: \.self) { flavour in
                    ProposedChip(text: flavour) {
                        add(flavour)
                    } remove: {
                        proposedFlavours.removeAll { $0 == flavour }
                        rejectedFlavours.insert(flavour.lowercased())
                    }
                }
                ForEach(suggestions, id: \.self) { flavour in
                    Chip(text: flavour, isOn: false) { add(flavour) }
                }
            }
            TextField("Add a flavour", text: $newFlavour)
                .font(.subheadline)
                .submitLabel(.done)
                .onSubmit { add(newFlavour) }
                .padding(10)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// Flavours used before and not on this cup yet.
    private var suggestions: [String] {
        let chosen = Set(evaluation.flavours.map { $0.lowercased() })
        return usedFlavours.filter { !chosen.contains($0.lowercased()) }.prefix(8).map { $0 }
    }

    private var notes: Binding<String> {
        Binding(get: { evaluation.notes ?? "" }, set: { evaluation.notes = $0.isEmpty ? nil : $0 })
    }

    private func add(_ flavour: String) {
        let trimmed = flavour.trimmingCharacters(in: .whitespacesAndNewlines)
        newFlavour = ""
        proposedFlavours.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        guard !trimmed.isEmpty, !evaluation.flavours.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        evaluation.flavours.append(trimmed)
    }
}

/// A tag the notes reader proposed: outlined and marked, so it reads as not
/// yet the drinker's. Tapping it keeps it; the × removes it.
struct ProposedChip: View {
    let text: String
    let keep: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: keep) {
                Label(text, systemImage: "sparkles")
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .frame(minHeight: 36)
            }
            .accessibilityLabel("Suggested: \(text)")
            .accessibilityHint("Keeps this tag")
            Button(action: remove) {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 36)
            }
            .accessibilityLabel("Remove \(text)")
        }
        .buttonStyle(.plain)
        .font(.footnote.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(Theme.accent)
        .overlay(Capsule().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
    }
}

/// A tag to tap on or off.
struct Chip: View {
    let text: String
    let isOn: Bool
    var removes = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(text)
                if removes { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
            }
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(isOn ? Theme.ground : Theme.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(isOn ? Theme.accent : Theme.raised, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(removes ? "Removes this flavour" : "")
    }
}

extension CharacterTag {
    var name: String { rawValue.capitalized }
}
