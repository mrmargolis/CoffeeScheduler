import CoffeeCore
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import Vision

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Reads a bag's label on the phone: Vision finds the text, and Apple's
/// on-device language model, where the phone has one, picks out the roaster
/// and the coffee. Nothing is sent anywhere.
enum LabelReader {
    /// The label's lines, top to bottom, and where each sits. Language correction leans
    /// towards `customWords`, so a roaster's name already in the app isn't
    /// "corrected" to a dictionary word.
    static func lines(in image: UIImage, customWords: [String]) async throws -> [BagLabel.Line] {
        try await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.customWords = customWords
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
            try handler.perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox
                return BagLabel.Line(text, x: box.minX, y: box.minY, width: box.width, height: box.height)
            }
            // Top to bottom, for the list of the label's text
            .sorted { $0.y + $0.height > $1.y + $1.height }
        }.value
    }

    /// The roaster and coffee: the language model's reading where it has
    /// one and it holds up against the label, `BagLabel.read`'s otherwise.
    static func reading(of lines: [BagLabel.Line], knownRoasters: [String]) async -> BagLabel.Reading {
        let guess = BagLabel.read(lines, knownRoasters: knownRoasters)
        guard !lines.isEmpty, let model = await modelReading(of: lines, knownRoasters: knownRoasters) else { return guess }
        return BagLabel.checked(model, guess: guess, lines: lines, knownRoasters: knownRoasters)
    }

    private static func modelReading(of lines: [BagLabel.Line], knownRoasters: [String]) async -> BagLabel.Reading? {
        #if canImport(FoundationModels)
            if #available(iOS 26, *) {
                guard case .available = SystemLanguageModel.default.availability else { return nil }
                let prompt = BagLabel.prompt(for: lines, knownRoasters: knownRoasters)
                guard let answer = try? await LanguageModelSession().respond(to: prompt).content else { return nil }
                return BagLabel.reading(fromModelAnswer: answer)
            }
        #endif
        return nil
    }
}

extension CGImagePropertyOrientation {
    /// The orientation Vision needs to read a photo the right way up.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// The camera, or the photo library where there's no camera (the Simulator).
/// Hands back the photo, or nil when cancelled.
struct LabelCamera: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

/// A photo already in the library. Hands back the photo, or nil when
/// cancelled; `onFailure` when the photo picked won't load. Needs no
/// permission: the picker runs outside the app.
struct LabelPhotoPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void
    let onFailure: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish, onFailure: onFailure) }

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinish: (UIImage?) -> Void
        let onFailure: () -> Void

        init(onFinish: @escaping (UIImage?) -> Void, onFailure: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onFailure = onFailure
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { return onFinish(nil) }
            guard provider.canLoadObject(ofClass: UIImage.self) else { return onFailure() }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let image = object as? UIImage
                Task { @MainActor in
                    if let image { self.onFinish(image) } else { self.onFailure() }
                }
            }
        }
    }
}
