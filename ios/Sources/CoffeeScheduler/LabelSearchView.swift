import CoffeeCore
import SafariServices
import SwiftUI

/// Photograph a bag, read its label on the phone, and look the coffee up on
/// Bean Base. The reading can be corrected before searching.
struct LabelSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.camera
    @State private var lines: [BagLabel.Line] = []
    @State private var reading = BagLabel.Reading(roaster: "", coffee: "")
    @State private var error: String?
    @State private var showingResults = false

    private enum Step {
        case camera
        case reading
        case review
    }

    var body: some View {
        if step == .camera {
            LabelCamera { image in
                guard let image else { return dismiss() }
                step = .reading
                Task { await read(image) }
            }
            .ignoresSafeArea()
        } else {
            NavigationStack {
                form
                    .navigationTitle("Bag label")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Retake") { step = .camera }.disabled(step == .reading)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
            .sheet(isPresented: $showingResults) {
                if let url = BagLabel.searchURL(for: reading) {
                    SafariView(url: url).ignoresSafeArea()
                }
            }
        }
    }

    private var form: some View {
        Form {
            Group {
                Section {
                    TextField("Coffee", text: $reading.coffee)
                    TextField("Roaster", text: $reading.roaster)
                    Button("Search Bean Base") { showingResults = true }
                        .disabled(step != .review || BagLabel.searchURL(for: reading) == nil)
                } header: {
                    Text("Search for")
                } footer: {
                    footer
                }
                if !lines.isEmpty {
                    Section {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            lineMenu(line.text)
                        }
                    } header: {
                        Text("Text on the label")
                    } footer: {
                        Text("Tap a line to use it instead.")
                    }
                }
            }
            .listRowBackground(Theme.card)
            .listRowSeparatorTint(Theme.hairline)
        }
        .themedList()
    }

    @ViewBuilder private var footer: some View {
        if step == .reading {
            HStack(spacing: 6) {
                ProgressView()
                Text("Reading the label…")
            }
        } else if let error {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.gapText)
        } else {
            Text("Read on this iPhone. Fix anything it got wrong before searching.")
        }
    }

    private func lineMenu(_ text: String) -> some View {
        Menu {
            Button("Use as coffee") { reading.coffee = text }
            Button("Use as roaster") { reading.roaster = text }
        } label: {
            Text(text).foregroundStyle(Theme.text2).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func read(_ image: UIImage) async {
        error = nil
        do {
            lines = try await LabelReader.lines(in: image, customWords: model.roasters)
            reading = await LabelReader.reading(of: lines, knownRoasters: model.roasters)
            if lines.isEmpty { error = "No text found. Retake the photo closer to the label." }
        } catch {
            lines = []
            self.error = "Couldn't read the photo: \(error.localizedDescription)"
        }
        step = .review
    }
}

/// Safari inside the app, so the search is one swipe from the app.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
