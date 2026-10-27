import CoffeeCore
import SwiftUI

/// What the label sheet opens on: a photo, and the field being typed in.
struct LabelPick: Identifiable {
    let photo: BagSource.ID
    /// The field to put a line in; nil to choose one for each line.
    let target: BagField?
    var id: BagSource.ID { photo }
}

/// The text read off each photo, a line at a time, in half a sheet so the
/// form shows above it. A line goes in the field being typed in, or in the
/// field picked for it.
struct BagLabelSheet: View {
    let photos: [BagSource]
    let target: BagField?
    let onPick: (String, BagField) -> Void
    @State private var shown: BagSource.ID
    @Environment(\.dismiss) private var dismiss

    /// The fields a line of text can go in.
    private static let fields = BagField.allCases.filter { $0.text != nil }

    init(photos: [BagSource], pick: LabelPick, onPick: @escaping (String, BagField) -> Void) {
        self.photos = photos
        target = pick.target
        self.onPick = onPick
        _shown = State(initialValue: pick.photo)
    }

    var body: some View {
        NavigationStack {
            List {
                if photos.count > 1 {
                    Picker("Photo", selection: $shown) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            Text("Photo \(index + 1)").tag(photo.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        row(line)
                    }
                } footer: {
                    Text(target.map { "Tap a line to put it in \($0.title.lowercased())." } ?? "Tap a line to put it in a field.")
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(target.map { "Pick the \($0.title.lowercased())" } ?? "Text on the label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.ground)
    }

    private var lines: [String] {
        guard case .photo(_, let lines) = photos.first(where: { $0.id == shown })?.kind else { return [] }
        return lines
    }

    @ViewBuilder private func row(_ line: String) -> some View {
        if let target {
            Button {
                onPick(BagLabel.tidy(line), target)
                dismiss()
            } label: {
                Text(line).foregroundStyle(Theme.text2).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Menu {
                ForEach(Self.fields, id: \.self) { field in
                    Button("Use as \(field.title.lowercased())") { onPick(BagLabel.tidy(line), field) }
                }
            } label: {
                Text(line).foregroundStyle(Theme.text2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
