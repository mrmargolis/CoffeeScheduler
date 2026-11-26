import CoffeeCore
import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Reads the notes typed on the evaluation sheet with Apple's on-device
/// language model, where the phone has one, and proposes character tags and
/// flavours. Nothing is sent anywhere.
///
/// Apple's larger Private Cloud Compute model (iOS 27) would read them
/// better, but needs the com.apple.developer.private-cloud-compute
/// entitlement from Apple (without it, a session stops the app) and an
/// iOS 27 SDK in CI.
struct NotesModelReader: NotesReader {
    /// Whether the evaluation sheet reads notes. On, to see how much its
    /// suggestions help in practice (#78); Settings › Dial-in › Check the
    /// notes reader runs it over real notes.
    static let isEnabled = true

    /// Whether the phone has the model ready, as the label reader asks.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    /// The reader for the evaluation sheet: nil while it's turned off or the
    /// phone has no model.
    static var forSheet: NotesModelReader? {
        isEnabled && isAvailable ? NotesModelReader() : nil
    }

    func read(_ notes: String) async -> NotesReading? {
        guard let answer = try? await answer(for: notes) else { return nil }
        return NotesPrompt.reading(fromAnswer: answer, notes: notes)
    }

    /// The model's answer as it gave it, for the check in Settings.
    func answer(for notes: String) async throws -> String {
        #if canImport(FoundationModels)
            if #available(iOS 26, *) {
                return try await LanguageModelSession().respond(to: NotesPrompt.prompt(for: notes)).content
            }
        #endif
        throw NotesReaderError("The notes reader needs Apple Intelligence, on iOS 26 or later.")
    }
}

struct NotesReaderError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
