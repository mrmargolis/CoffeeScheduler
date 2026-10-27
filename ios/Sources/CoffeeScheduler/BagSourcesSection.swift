import CoffeeCore
import SwiftUI

/// The top of Add a bag: before anything's read, where to start; after, a
/// tile for each photo and page in the order they were used, how much is
/// filled in, and what the last one replaced.
struct BagSourcesSection: View {
    let intake: BagIntake
    /// A photo's tile was tapped: show the text read off it.
    let onPickText: (BagSource) -> Void
    let onTakePhoto: () -> Void

    var body: some View {
        Section {
            if intake.sources.isEmpty {
                StartPrompt(onTakePhoto: onTakePhoto)
            } else {
                strip
                ForEach(intake.lastFill?.replaced ?? [], id: \.field) { replacement in
                    ReplacedRow(
                        replacement: replacement, now: intake.draft.value(replacement.field) ?? "", source: intake.lastSourceName
                    ) { intake.keep(replacement) }
                }
                if needsThePhoto {
                    BagPhotoNudge(onTakePhoto: onTakePhoto)
                }
            }
        }
    }

    /// Read only from pages, which don't give the roast date or weight.
    private var needsThePhoto: Bool {
        intake.photos.isEmpty && (intake.draft.roastDate == nil || intake.draft.weightGrams == nil)
    }

    private var strip: some View {
        HStack(spacing: 10) {
            ForEach(intake.sources) { source in
                SourceTile(source: source) { onPickText(source) }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(headline).font(.subheadline.weight(.semibold))
                if !intake.photos.isEmpty {
                    Text("Tap a photo to pick text from it").font(.caption).foregroundStyle(Theme.text3)
                }
                guesses
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private var headline: String {
        let filled = intake.draft.count(BagField.allCases).filled
        return "\(filled) of \(BagField.allCases.count) filled"
    }

    @ViewBuilder private var guesses: some View {
        let count = intake.draft.count(BagField.allCases).guesses
        if count > 0 {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) \(count == 1 ? "guess" : "guesses")")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text("Tap Guess on a right one to keep it").font(.caption).foregroundStyle(Theme.text3)
            }
        } else {
            Label("No guesses", systemImage: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ready)
        }
    }
}

/// Before anything's read: photograph the front, then the back. The whole
/// prompt opens the camera, as the bar's Camera button does.
private struct StartPrompt: View {
    let onTakePhoto: () -> Void

    var body: some View {
        Button(action: onTakePhoto) { prompt }
            .buttonStyle(.borderless)
            .accessibilityHint("Opens the camera")
    }

    private var prompt: some View {
        HStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.title3)
                .foregroundStyle(Theme.ground)
                .frame(width: 48, height: 48)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Photograph the front, then the back")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text("Or find the coffee's page. Each fills what's empty and replaces guesses; what you type stays.")
                    .font(.caption)
                    .foregroundStyle(Theme.text3)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text3)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// A photo, shown small, or the page, as a globe.
private struct SourceTile: View {
    let source: BagSource
    let action: () -> Void

    var body: some View {
        switch source.kind {
        case .photo(let image, _):
            Button(action: action) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Pick text from this photo")
        case .page(let host):
            VStack(spacing: 4) {
                Image(systemName: "globe").font(.title3).foregroundStyle(Theme.accent)
                Text("Page").font(.caption2.weight(.bold)).foregroundStyle(Theme.text2)
            }
            .frame(width: 52, height: 60)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Filled from \(host)")
        }
    }
}

/// A value the last photo or page replaced, with a button to put it back.
private struct ReplacedRow: View {
    let replacement: BagFill.Replacement
    /// What it holds now.
    let now: String
    let source: String
    let keep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Replaced from \(source)").font(.caption).foregroundStyle(Theme.text3)
            HStack {
                let field = replacement.field
                Text("\(field.title): \(Text(Self.shown(replacement.old, field)).strikethrough()) → \(Self.shown(now, field))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.text2)
                Spacer(minLength: 8)
                Button("Keep old", action: keep)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Keep \(replacement.old) as the \(replacement.field.title.lowercased())")
            }
        }
        .padding(.vertical, 4)
    }

    static func shown(_ value: String, _ field: BagField) -> String {
        switch field {
        case .roastDate: Format.mediumDay(value)
        case .weight: "\(value) g"
        default: value
        }
    }
}

/// After only pages: the roast date and weight are on the bag.
struct BagPhotoNudge: View {
    let onTakePhoto: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera").foregroundStyle(Theme.accent)
            Text("The roast date and weight come from the bag itself.").font(.subheadline)
            Spacer(minLength: 4)
            Button("Photo", action: onTakePhoto)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Theme.ground)
                .buttonBorderShape(.capsule)
        }
        .padding(.vertical, 4)
    }
}
