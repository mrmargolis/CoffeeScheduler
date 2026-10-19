import CoffeeCore
import ImageIO
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
    /// The label's lines, top to bottom.
    static func lines(in image: UIImage) async throws -> [BagLabel.Line] {
        try await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
            try handler.perform([request])
            return (request.results ?? []).compactMap { observation in
                observation.topCandidates(1).first.map { BagLabel.Line($0.string, height: Double(observation.boundingBox.height)) }
            }
        }.value
    }

    /// The roaster and coffee: the language model's reading where it has
    /// one, filled in from the label's biggest text where it doesn't.
    static func reading(of lines: [BagLabel.Line], knownRoasters: [String]) async -> BagLabel.Reading {
        let guess = BagLabel.read(lines, knownRoasters: knownRoasters)
        guard !lines.isEmpty, let model = await modelReading(of: lines, knownRoasters: knownRoasters) else { return guess }
        return BagLabel.Reading(
            roaster: model.roaster.isEmpty ? guess.roaster : model.roaster,
            coffee: model.coffee.isEmpty ? guess.coffee : model.coffee
        )
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
