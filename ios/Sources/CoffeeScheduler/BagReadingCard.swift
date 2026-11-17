import SwiftUI
import UIKit

/// A photo being read, and how far along: shown over Add a bag until its
/// fields fill in, since reading takes a moment or two.
struct BagReading {
    let photo: UIImage
    var step = "Finding the text…"
}

/// Over the form while a photo is read, so the pause after taking one says
/// what's happening.
struct BagReadingCard: View {
    let reading: BagReading

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.35)).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(uiImage: reading.photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.25)) }
                    .overlay { ProgressView().controlSize(.large).tint(.white) }
                    .accessibilityHidden(true)
                Text("Reading the label")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Text(reading.step)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text2)
                    .contentTransition(.opacity)
                    .animation(.default, value: reading.step)
            }
            .padding(24)
            .frame(maxWidth: 260)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .combine)
        }
        .transition(.opacity)
    }
}

/// Photos waiting to be read, read one at a time in the order they were
/// taken. A class, not view state, so a photo taken while another is read
/// joins the same list the reading loop is working through.
@MainActor
@Observable
final class LabelQueue {
    /// The photo being read, for the card over the form.
    private(set) var reading: BagReading?
    private var waiting: [UIImage] = []
    private var running = false

    /// Queues `image`, and starts reading if nothing is.
    func add(_ image: UIImage, read: @escaping @MainActor (UIImage) async -> Void) {
        waiting.append(image)
        guard !running else { return }
        running = true
        reading = BagReading(photo: image)
        Task {
            while !waiting.isEmpty {
                let next = waiting.removeFirst()
                reading = BagReading(photo: next)
                await read(next)
            }
            reading = nil
            running = false
        }
    }

    /// What the card says it's doing now.
    func step(_ text: String) {
        reading?.step = text
    }
}
