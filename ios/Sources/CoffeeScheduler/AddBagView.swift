import CoffeeCore
import SwiftUI

/// A bag to add to BeanConqueror, filled in from photos of its label (read
/// on the phone), from its page on the roaster's site or Bean Base, and by
/// hand, in any mix and any order.
struct AddBagView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var intake: BagIntake
    @State private var showingCamera = false
    @State private var choosingPhoto = false
    /// The photo picker asked for over the camera, which it's shown on.
    @State private var choosingOverCamera = false
    @State private var browsing: Browse?
    @State private var discarding: Discard?
    /// The coffee sent to BeanConqueror, to clear the form for the next bag
    /// on coming back.
    @State private var sent: String?
    /// The photo being read, for the card over the form.
    @State private var reading: BagReading?

    private struct Browse: Identifiable {
        let url: URL
        var id: URL { url }
    }

    /// Clear and Done both throw a filled-in bag away, so they ask first.
    private enum Discard { case clear, close }

    /// Whether "Notes and origin" starts open: it does, but a screenshot
    /// shows it folded.
    private let showsOrigin: Bool

    init(intake: BagIntake = BagIntake(), showsOrigin: Bool = true) {
        _intake = State(initialValue: intake)
        self.showsOrigin = showsOrigin
    }

    var body: some View {
        NavigationStack {
            BagDraftForm(intake: intake, actions: actions, originOpen: showsOrigin)
                .navigationTitle("Add a bag")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .overlay {
            if let reading { BagReadingCard(reading: reading) }
        }
        .animation(.easeInOut(duration: 0.2), value: reading == nil)
        .fullScreenCover(isPresented: $showingCamera) { camera }
        .sheet(isPresented: $choosingPhoto) { picker }
        .sheet(item: $browsing) { browse in
            PageBrowser(start: browse.url) { page in fill(from: page) }
        }
        .confirmationDialog("Discard this bag?", isPresented: discardingShown, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                if discarding == .close { dismiss() } else { intake.clear() }
            }
        } message: {
            Text("What's filled in so far goes.")
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let coffee = sent else { return }
            sent = nil
            intake.clear()
            intake.status = .filled("Sent \(coffee) to BeanConqueror. Ready for the next bag.")
        }
    }

    private var actions: BagDockActions {
        BagDockActions(
            takePhoto: { showingCamera = true },
            choosePhoto: { choosingPhoto = true },
            search: { browsing = Browse(url: $0.url(for: intake.draft)) },
            add: addToBeanConqueror)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Clear") { ask(.clear) }.disabled(intake.status == .reading || intake.isEmpty)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { ask(.close) }
        }
    }

    private var discardingShown: Binding<Bool> {
        Binding {
            discarding != nil
        } set: {
            if !$0 { discarding = nil }
        }
    }

    private func ask(_ discard: Discard) {
        if intake.isEmpty || sent != nil {
            if discard == .close { dismiss() } else { intake.clear() }
        } else {
            discarding = discard
        }
    }

    /// The camera, over the form so it keeps its place, with a button for a
    /// photo already taken.
    private var camera: some View {
        LabelCamera { image in
            showingCamera = false
            if let image { startReading(image) }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            Button("Choose from Photos", systemImage: "photo.on.rectangle") { choosingOverCamera = true }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 56)
        }
        .sheet(isPresented: $choosingOverCamera) { picker }
    }

    private var picker: some View {
        LabelPhotoPicker { image in
            choosingPhoto = false
            choosingOverCamera = false
            showingCamera = false
            if let image { startReading(image) }
        } onFailure: {
            choosingPhoto = false
            choosingOverCamera = false
            showingCamera = false
            intake.status = .failed("Couldn't open that photo. Take it again or choose another.")
        }
        .ignoresSafeArea()
    }

    private func startReading(_ image: UIImage) {
        intake.status = .reading
        reading = BagReading(photo: image)
        Task {
            await read(image)
            reading = nil
        }
    }

    private func read(_ image: UIImage) async {
        do {
            let lines = try await LabelReader.lines(in: image, customWords: model.roasters)
            guard !lines.isEmpty else {
                intake.status = .failed("No text found. Take the photo closer to the label.")
                return
            }
            reading?.step = "Picking out the coffee and roaster…"
            var found = BagLabel.details(in: lines, today: DateUtils.today())
            let reading = await LabelReader.reading(of: lines, knownRoasters: model.roasters).tidied
            found.take(reading, knownRoasters: model.roasters)
            intake.fill(found, from: .photo(Self.upright(image), lines: lines))
        } catch {
            intake.status = .failed("Couldn't read the photo: \(error.localizedDescription)")
        }
    }

    private func fill(from page: PageContent) {
        let found = BagLabel.details(
            of: BagLabel.Page(
                heading: page.heading, title: page.title, site: page.site, text: page.text, url: page.url,
                summary: page.summary),
            knownRoasters: model.roasters, today: DateUtils.today())
        let lines = (page.text.split(whereSeparator: \.isNewline).map(String.init) + page.summary.components(separatedBy: ". "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        intake.fill(found, from: .page(host: URL(string: page.url)?.host() ?? "the page", lines: lines))
    }

    /// The photo the right way up, at most 1,600 pixels on its long side:
    /// big enough to tap its text, small enough to keep a few.
    private static func upright(_ image: UIImage) -> UIImage {
        let scale = min(1, 1600 / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func addToBeanConqueror() {
        guard let url = BeanConquerorLink.url(for: intake.draft) else { return }
        openURL(url) { opened in
            if opened {
                sent = intake.draft.coffee
            } else {
                intake.status = .failed("Couldn't open BeanConqueror. Is it installed?")
            }
        }
    }
}
