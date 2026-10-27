import CoffeeCore
import SwiftUI

/// What the text picker opens on: a photo or page, and the field being
/// typed in, if any.
struct TextPick: Identifiable {
    let source: BagSource.ID
    /// The field a tapped line goes straight into; nil to choose one for it.
    let target: BagField?
    var id: BagSource.ID { source }
}

/// The text on a photo, outlined where it sits, or a page's, a line at a
/// time. Tap a line, then the field it belongs in; the fields it looks
/// like are gold. Opened for a field being typed in, a tapped line goes
/// straight there.
struct BagTextPicker: View {
    let intake: BagIntake
    let target: BagField?
    @State private var shown: BagSource.ID
    @State private var selected: Int?
    /// A photo's text as a list, for lines too small to tap on the photo.
    @State private var asList = false
    @Environment(\.dismiss) private var dismiss
    private let today = DateUtils.today()

    init(intake: BagIntake, pick: TextPick) {
        self.intake = intake
        target = pick.target
        _shown = State(initialValue: pick.source)
    }

    private var source: BagSource? { intake.sources.first { $0.id == shown } }
    private var lines: [String] { source?.lines ?? [] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if case .photo(let image, let boxes) = source?.kind, !asList {
                    OutlinedPhoto(image: image, lines: boxes, selected: $selected, onTap: tapped)
                } else {
                    LineList(lines: lines, selected: selected, onTap: tapped)
                }
                panel
            }
            .background(Theme.ground)
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: shown) { selected = nil }
        }
        .presentationBackground(Theme.ground)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if intake.sources.count > 1 {
                Picker("Source", selection: $shown) {
                    ForEach(Array(intake.sources.enumerated()), id: \.element.id) { index, source in
                        Text(name(of: source, at: index)).tag(source.id)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Text(target.map { "Pick the \($0.title.lowercased())" } ?? "Pick text")
            }
        }
        ToolbarItem(placement: .cancellationAction) {
            if source?.isPhoto == true {
                Button(asList ? "Photo" : "List") { asList.toggle() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }.fontWeight(.semibold)
        }
    }

    private func name(of source: BagSource, at index: Int) -> String {
        guard source.isPhoto else { return "Page" }
        return "Photo \(intake.sources[...index].count(where: \.isPhoto))"
    }

    @ViewBuilder private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let target {
                Text("Tap the text for \(target.title.lowercased()).").foregroundStyle(Theme.text2)
            } else if let selected, lines.indices.contains(selected) {
                Text("Put \(Text("“\(lines[selected])”").foregroundStyle(Theme.text)) in").foregroundStyle(Theme.text2)
                    .lineLimit(2)
                FieldTiles(intake: intake, line: lines[selected], today: today) { field, value in
                    intake.pick(value, for: field)
                    self.selected = nil
                }
            } else {
                Text("Tap the text you want, then the field it goes in.").foregroundStyle(Theme.text3)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card)
    }

    private func tapped(_ index: Int) {
        guard let target else {
            selected = index
            return
        }
        if let value = BagLabel.value(in: lines[index], for: target, today: today) {
            intake.pick(value, for: target)
            dismiss()
        } else {
            intake.status = .failed("No \(target.title.lowercased()) in that line.")
            selected = index
        }
    }
}

/// The photo, fitted to the space, with a box over each line of text.
private struct OutlinedPhoto: View {
    let image: UIImage
    let lines: [BagLabel.Line]
    @Binding var selected: Int?
    let onTap: (Int) -> Void

    var body: some View {
        GeometryReader { space in
            let size = fitted(in: space.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    box(line, index: index, in: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
    }

    private func box(_ line: BagLabel.Line, index: Int, in size: CGSize) -> some View {
        let frame = line.frame(width: size.width, height: size.height)
        let isSelected = selected == index
        return Button {
            onTap(index)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.accent.opacity(isSelected ? 0.4 : 0.12))
                .strokeBorder(Theme.accent.opacity(isSelected ? 1 : 0.7), lineWidth: isSelected ? 2 : 1)
                // Small text still gets a box big enough to tap
                .frame(width: max(frame.width + 6, 24), height: max(frame.height + 6, 24))
        }
        .buttonStyle(.plain)
        .position(x: frame.midX, y: frame.midY)
        .accessibilityLabel(line.text)
    }

    /// The photo's size scaled to fit `space`, keeping its shape.
    private func fitted(in space: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else { return space }
        let scale = min(space.width / image.size.width, space.height / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }
}

/// A page's text, or a photo's as a list, a line at a time.
private struct LineList: View {
    let lines: [String]
    let selected: Int?
    let onTap: (Int) -> Void

    var body: some View {
        List {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Button {
                    onTap(index)
                } label: {
                    Text(line)
                        .foregroundStyle(selected == index ? Theme.text : Theme.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowBackground(selected == index ? Theme.accent.opacity(0.2) : Theme.card)
            }
        }
        .themedList()
    }
}

/// A tile for each field, showing what it holds: gold for the fields the
/// line looks like it holds, outlined for a guess or an empty field.
private struct FieldTiles: View {
    let intake: BagIntake
    let line: String
    let today: String
    let onPick: (BagField, String) -> Void

    var body: some View {
        let likely = BagLabel.likelyFields(in: line, today: today)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(BagField.allCases, id: \.self) { field in
                let value = BagLabel.value(in: line, for: field, today: today)
                Button {
                    if let value { onPick(field, value) }
                } label: {
                    tile(field, isLikely: likely.contains(field))
                }
                .buttonStyle(.plain)
                .disabled(value == nil)
                .opacity(value == nil ? 0.4 : 1)
            }
        }
    }

    private func tile(_ field: BagField, isLikely: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        let isGuess = intake.draft.isGuess(field)
        let isEmpty = !intake.draft.has(field)
        return VStack(alignment: .leading, spacing: 2) {
            Text(field.title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(isLikely ? Theme.ground : isGuess ? Theme.accent : Theme.text3)
            Text(shown(field))
                .font(.footnote)
                .foregroundStyle(isLikely ? Theme.ground : isEmpty ? Theme.text3 : Theme.text)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isLikely ? Theme.accent : isEmpty ? .clear : Theme.raised, in: shape)
        .overlay(shape.strokeBorder(isGuess && !isLikely ? Theme.accent : isEmpty ? Theme.hairline : .clear))
    }

    private func shown(_ field: BagField) -> String {
        guard let value = intake.draft.value(field), intake.draft.has(field) else { return "Empty" }
        switch field {
        case .roastDate: return Format.mediumDay(value)
        case .weight: return "\(value) g"
        default: return value
        }
    }
}
