import CoffeeCore
import SwiftUI

/// A bag to add to BeanConqueror, filled in from photos of its label (read
/// on the phone), from its page on the roaster's site or Bean Base, and by
/// hand, in any mix.
struct AddBagView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showingCamera = false
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
        Group {
            if showingCamera {
                camera
            } else {
                formScreen
            }
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

    private var formScreen: some View {
        NavigationStack {
            form
                .navigationTitle("Add a bag")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear", action: clear).disabled(status == .reading || (draft == BagDraft() && photos.isEmpty))
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

    private var form: some View {
        BagDraftForm(
            draft: $draft,
            labelText: photos.flatMap { $0.map(\.text) },
            status: status,
            onAdd: addToBeanConqueror,
            onTakePhoto: { showingCamera = true },
            onChoosePhoto: { choosingPhoto = true },
            onSearch: { search in
                browsing = Browse(url: search.url(for: draft))
            })
    }

    /// The camera, with a button over it for a photo already taken.
    private var camera: some View {
        LabelCamera { image in
            if let image {
                startReading(image)
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
            found.reading = await LabelReader.reading(of: lines, knownRoasters: model.roasters).tidied
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

    private func clear() {
        draft = BagDraft()
        photos = []
        status = .ready
    }
}
