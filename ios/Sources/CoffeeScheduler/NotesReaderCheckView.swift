import CoffeeCore
import SwiftUI

/// Runs the notes reader over real notes, to check its prompt before it's
/// turned on for the evaluation sheet: the newest imported brews' notes,
/// which mix recipes, plans and tasting, and any notes typed here. Each
/// shows the tags it would propose and the model's answer as given.
struct NotesReaderCheckView: View {
    @Environment(AppModel.self) private var model
    @State private var samples: [Sample] = []
    @State private var typed = ""
    @State private var typedSample: Sample?
    @State private var isReading = false

    /// How many brews' notes to check.
    static let sampleCount = 12

    struct Sample: Identifiable {
        let id: String
        let notes: String
        var answer: String?
        var isRead = false

        var reading: NotesReading? { answer.map(NotesPrompt.reading(fromAnswer:)) }
    }

    var body: some View {
        List {
            if !NotesModelReader.isAvailable {
                Text("The notes reader needs Apple Intelligence, on iOS 26 or later.").foregroundStyle(Theme.text2)
            }
            Section {
                TextField("Notes to try", text: $typed, axis: .vertical).lineLimit(3...8)
                Button("Read these notes") { Task { await readTyped() } }
                    .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isReading)
                if let typedSample { SampleRow(sample: typedSample) }
            } header: {
                SectionLabel(title: "Try notes").listRowInsets(Theme.labelInsets)
            }
            Section {
                if samples.isEmpty {
                    Text("Import a BeanConqueror export with brew notes to check against.").foregroundStyle(Theme.text2)
                }
                ForEach(samples) { SampleRow(sample: $0) }
            } header: {
                SectionLabel(title: "Your newest brew notes").listRowInsets(Theme.labelInsets)
            } footer: {
                SectionFooter(
                    text: """
                        Tags it should find only from how the cup tasted, never from recipe lines or plans. \
                        Sharp is sour or harsh acidity, not just more of it.
                        """)
            }
        }
        .listRowBackground(Theme.card)
        .themedList()
        .navigationTitle("Notes reader")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isReading ? "Reading…" : "Read all") { Task { await readAll() } }
                    .disabled(isReading || samples.isEmpty || !NotesModelReader.isAvailable)
            }
        }
        .onAppear {
            if samples.isEmpty {
                samples = model.recentBrewNotes(limit: Self.sampleCount).map { Sample(id: $0.id, notes: $0.notes ?? "") }
            }
        }
    }

    /// One at a time: the model runs one session at a time anyway.
    private func readAll() async {
        isReading = true
        defer { isReading = false }
        for index in samples.indices {
            let answer = await NotesModelReader().answer(for: samples[index].notes)
            samples[index].answer = answer
            samples[index].isRead = true
        }
    }

    private func readTyped() async {
        isReading = true
        defer { isReading = false }
        var sample = Sample(id: "typed", notes: typed)
        sample.answer = await NotesModelReader().answer(for: typed)
        sample.isRead = true
        typedSample = sample
    }
}

/// A sample's notes, then what the reader made of them.
private struct SampleRow: View {
    let sample: NotesReaderCheckView.Sample

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sample.notes).font(.footnote).foregroundStyle(Theme.text2)
            if let reading = sample.reading {
                Text("Character: \(character(reading))").font(.subheadline.weight(.semibold))
                Text("Flavours: \(reading.flavours.isEmpty ? "none" : reading.flavours.joined(separator: ", "))")
                    .font(.subheadline.weight(.semibold))
                if let answer = sample.answer {
                    Text(answer).font(.caption.monospaced()).foregroundStyle(Theme.text3)
                }
            } else if sample.isRead {
                Text("No answer from the model.").font(.subheadline).foregroundStyle(Theme.gapText)
            }
        }
        .padding(.vertical, 4)
        .textSelection(.enabled)
    }

    private func character(_ reading: NotesReading) -> String {
        let tags = CharacterTag.allCases.filter(reading.character.contains).map(\.name)
        return tags.isEmpty ? "none" : tags.joined(separator: ", ")
    }
}
