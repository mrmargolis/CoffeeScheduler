import CoffeeCore
import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Reads the notes typed on the evaluation sheet with Apple's on-device
/// language model, where the phone has one, and proposes character tags and
/// flavours. Nothing is sent anywhere.
struct NotesModelReader: NotesReader {
    /// Off until its output has been checked against real notes and the
    /// prompt approved (#78). Until then the evaluation sheet works as it
    /// always has, and Settings › Dial-in shows the check.
    static let isEnabled = false

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
        await answer(for: notes).map { NotesPrompt.reading(fromAnswer: $0, notes: notes) }
    }

    /// The model's answer as it gave it, for the check in Settings.
    func answer(for notes: String) async -> String? {
        #if canImport(FoundationModels)
            if #available(iOS 26, *) {
                guard case .available = SystemLanguageModel.default.availability else { return nil }
                return try? await LanguageModelSession().respond(to: NotesPrompt.prompt(for: notes)).content
            }
        #endif
        return nil
    }
}
