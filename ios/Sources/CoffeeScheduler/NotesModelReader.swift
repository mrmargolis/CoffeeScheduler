import CoffeeCore
import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Reads the notes typed on the evaluation sheet with one of Apple's
/// language models and proposes character tags and flavours.
struct NotesModelReader: NotesReader {
    /// Whether the evaluation sheet reads notes. On, with the on-device
    /// model, to see how much its suggestions help in practice (#78);
    /// Settings › Dial-in › Check the notes reader runs it over real notes.
    static let isEnabled = true

    /// Whether the app is signed with Private Cloud Compute's entitlement
    /// (com.apple.developer.private-cloud-compute), which Apple grants on
    /// request. Without it, a session on that model stops the app rather
    /// than throwing, so the model is offered only once it's set up.
    static let hasCloudEntitlement = false

    /// Which of Apple's models reads the notes.
    enum Model: String, CaseIterable, Identifiable {
        /// Apple's larger model on Private Cloud Compute (iOS 27): the notes
        /// leave the phone for Apple's servers, which keep nothing.
        case cloud
        /// The small model on the phone (iOS 26): nothing leaves it.
        case onDevice

        var id: String { rawValue }

        var name: String {
            switch self {
            case .cloud: "Private Cloud Compute"
            case .onDevice: "On this phone"
            }
        }

        var isAvailable: Bool {
            #if canImport(FoundationModels)
                switch self {
                case .cloud:
                    guard NotesModelReader.hasCloudEntitlement else { return false }
                    if #available(iOS 27, *) { return PrivateCloudComputeLanguageModel().isAvailable }
                case .onDevice:
                    if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability { return true }
                }
            #endif
            return false
        }

        /// The bigger model when the phone can use it.
        static var preferred: Model? {
            allCases.first(where: \.isAvailable)
        }
    }

    var model: Model

    /// Whether the phone can use any of the models.
    static var isAvailable: Bool { Model.preferred != nil }

    /// The reader for the evaluation sheet: nil while it's turned off or the
    /// phone has no model.
    static var forSheet: NotesModelReader? {
        guard isEnabled, let model = Model.preferred else { return nil }
        return NotesModelReader(model: model)
    }

    func read(_ notes: String) async -> NotesReading? {
        guard let answer = try? await answer(for: notes) else { return nil }
        return NotesPrompt.reading(fromAnswer: answer, notes: notes)
    }

    /// The model's answer as it gave it, for the check in Settings.
    func answer(for notes: String) async throws -> String {
        let prompt = NotesPrompt.prompt(for: notes)
        #if canImport(FoundationModels)
            switch model {
            case .cloud:
                guard Self.hasCloudEntitlement else { throw NotesReaderError("Private Cloud Compute needs an entitlement from Apple first.") }
                if #available(iOS 27, *) {
                    return try await LanguageModelSession(model: PrivateCloudComputeLanguageModel()).respond(to: prompt).content
                }
            case .onDevice:
                if #available(iOS 26, *) {
                    return try await LanguageModelSession().respond(to: prompt).content
                }
            }
        #endif
        throw NotesReaderError("\(model.name) isn't available on this phone.")
    }
}

struct NotesReaderError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
