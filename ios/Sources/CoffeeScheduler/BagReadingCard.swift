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
