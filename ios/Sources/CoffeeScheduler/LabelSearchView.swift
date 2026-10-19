import CoffeeCore
import SwiftUI

/// Photograph a bag, or pick a photo of one, and read its label on the
/// phone; add photos of its other side and the roaster's page for what the
/// label leaves out; correct anything by hand; and add it to BeanConqueror.
struct LabelSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showingCamera = true
    @State private var choosingPhoto = false
    @State private var draft = BagDraft()
    /// Each photo's lines, in reading order.
    @State private var photos: [[BagLabel.Line]] = []
    @State private var status = ScanStatus.ready
    @State private var browsing: Browse?

    private struct Browse: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        if showingCamera {
            camera
        } else {
            NavigationStack {
                form
                    .navigationTitle("Add a bag")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Start over", action: startOver).disabled(status == .reading)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
            .sheet(item: $browsing) { browse in
                PageBrowser(start: browse.url) { page in
                    fill(
                        BagLabel.details(ofPage: page.text, title: page.title, site: page.site, url: page.url, today: DateUtils.today()),
                        from: URL(string: page.url)?.host() ?? "the page")
                }
            }
        }
    }

    private var form: some View {
        BagDraftForm(
            draft: $draft,
            labelText: photos.flatMap { $0.map(\.text) },
            status: status,
            onAdd: addToBeanConqueror,
            onAddPhoto: { showingCamera = true },
            onSearch: { search in
                browsing = search.url(for: draft).map(Browse.init)
            })
    }

    /// The camera, with a button over it for a photo already taken.
    /// Cancelling goes back to the bag, or closes the screen before there's one.
    private var camera: some View {
        LabelCamera { image in
            if let image {
                startReading(image)
            } else if photos.isEmpty && draft == BagDraft() {
                dismiss()
            } else {
                showingCamera = false
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            Button("Choose from Photos", systemImage: "photo.on.rectangle") { choosingPhoto = true }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 56)
        }
        .sheet(isPresented: $choosingPhoto) {
            LabelPhotoPicker { image in
                choosingPhoto = false
                if let image { startReading(image) }
            } onFailure: {
                choosingPhoto = false
                showingCamera = false
                status = .failed("Couldn't open that photo. Take it again or choose another.")
            }
            .ignoresSafeArea()
        }
    }

    private func startReading(_ image: UIImage) {
        showingCamera = false
        status = .reading
        Task { await read(image) }
    }

    private func read(_ image: UIImage) async {
        do {
            let lines = try await LabelReader.lines(in: image, customWords: model.roasters)
            guard !lines.isEmpty else {
                status = .failed("No text found. Take the photo closer to the label.")
                return
            }
            var found = BagLabel.details(in: lines, today: DateUtils.today())
            found.reading = await LabelReader.reading(of: lines, knownRoasters: model.roasters)
            photos.append(lines)
            fill(found, from: photos.count == 1 ? "the photo" : "photo \(photos.count)")
        } catch {
            status = .failed("Couldn't read the photo: \(error.localizedDescription)")
        }
    }

    /// Fills what's still empty from a photo or page, and says how much.
    private func fill(_ found: BagDraft, from source: String) {
        let before = draft.filledCount
        draft = draft.filling(from: found)
        let added = draft.filledCount - before
        status = .filled(
            added == 0
                ? "Nothing more from \(source). Fill in the rest by hand."
                : "Filled \(added) \(added == 1 ? "field" : "fields") from \(source). Check them before adding.")
    }

    private func addToBeanConqueror() {
        guard let url = BeanConquerorLink.url(for: draft) else { return }
        openURL(url) { opened in
            if !opened {
                status = .failed("Couldn't open BeanConqueror. Is it installed?")
            }
        }
    }

    private func startOver() {
        draft = BagDraft()
        photos = []
        status = .ready
        showingCamera = true
    }
}
