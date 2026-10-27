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
/// time, over a tile for each field. Either order works: a line, then the
/// field it goes in (the fields it looks like are gold), or a field, then
/// its line. Opened for a field being typed in, that field is chosen, and
/// the sheet closes once it's filled.
struct BagTextPicker: View {
    let intake: BagIntake
    let target: BagField?
    @State private var shown: BagSource.ID
    @State private var selected: Int?
    @State private var chosen: BagField?
    /// Why the last pick didn't go in: no date in the line, say.
    @State private var problem: String?
    /// A photo's text as a list, for lines too small to tap on the photo.
    @State private var asList = false
    @Environment(\.dismiss) private var dismiss
    private let today = DateUtils.today()

    init(intake: BagIntake, pick: TextPick) {
        self.intake = intake
        target = pick.target
        _shown = State(initialValue: pick.source)
        _chosen = State(initialValue: pick.target)
    }

    private var source: BagSource? { intake.sources.first { $0.id == shown } }
    private var lines: [String] { source?.lines ?? [] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if case .photo(let image, let boxes) = source?.kind, !asList {
                    OutlinedPhoto(image: image, lines: boxes, selected: $selected, onTap: tapped)
                        .id(shown)
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

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            hint.lineLimit(2)
            FieldTiles(
                intake: intake, line: selected.flatMap { lines.indices.contains($0) ? lines[$0] : nil }, chosen: chosen,
                today: today, onTap: tappedField)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card)
    }

    @ViewBuilder private var hint: some View {
        if let problem {
            Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.gapText)
        } else if let selected, lines.indices.contains(selected) {
            Text("Put \(Text("“\(lines[selected])”").foregroundStyle(Theme.text)) in…").foregroundStyle(Theme.text2)
        } else if let chosen {
            Text("Now tap the text for \(Text(chosen.title.lowercased()).foregroundStyle(Theme.text)).").foregroundStyle(Theme.text2)
        } else {
            Text("Tap the text, then the field it goes in. Or a field, then its text.").foregroundStyle(Theme.text3)
        }
    }

    /// A line tapped: into the chosen field, or picked to choose one for.
    private func tapped(_ index: Int) {
        problem = nil
        if let chosen {
            put(index, in: chosen)
        } else {
            selected = selected == index ? nil : index
        }
    }

    /// A field tapped: the picked line goes in, or it waits for one.
    private func tappedField(_ field: BagField) {
        problem = nil
        if let selected {
            put(selected, in: field)
        } else {
            chosen = chosen == field ? nil : field
        }
    }

    private func put(_ index: Int, in field: BagField) {
        guard let value = BagLabel.value(in: lines[index], for: field, today: today) else {
            problem = "No \(field.title.lowercased()) in “\(lines[index])”."
            return
        }
        intake.pick(value, for: field)
        selected = nil
        chosen = nil
        if target != nil { dismiss() }
    }
}

/// The photo, fitted to the space, with a box over each line of text.
/// Pinch to zoom in on small text, and drag to move around it.
private struct OutlinedPhoto: View {
    let image: UIImage
    let lines: [BagLabel.Line]
    @Binding var selected: Int?
    let onTap: (Int) -> Void
    @State private var zoom = Zoom()

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
            .scaleEffect(zoom.scale)
            .offset(zoom.offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(gestures(fitting: size))
            .clipped()
            .overlay(alignment: .bottomTrailing) { fitButton }
        }
        .background(Color.black)
    }

    @ViewBuilder private var fitButton: some View {
        if zoom.scale > 1 {
            Button("Fit") { withAnimation { zoom = Zoom() } }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
        }
    }

    /// Pinch to zoom, and drag to move once zoomed; a short tap still
    /// reaches a box.
    private func gestures(fitting size: CGSize) -> some Gesture {
        let pinch = MagnifyGesture()
            .onChanged { zoom.pinch(by: $0.magnification) }
            .onEnded { _ in withAnimation { zoom.settle(fitting: size) } }
        let drag = DragGesture(minimumDistance: 8)
            .onChanged { zoom.drag(by: $0.translation) }
            .onEnded { _ in withAnimation { zoom.settle(fitting: size) } }
        return pinch.simultaneously(with: drag)
    }

    private func box(_ line: BagLabel.Line, index: Int, in size: CGSize) -> some View {
        let frame = line.frame(width: size.width, height: size.height)
        let isSelected = selected == index
        // Sizes on screen stay the same however far it's zoomed
        let point = 1 / zoom.scale
        return Button {
            onTap(index)
        } label: {
            RoundedRectangle(cornerRadius: 4 * point)
                .fill(Theme.accent.opacity(isSelected ? 0.4 : 0.12))
                .strokeBorder(Theme.accent.opacity(isSelected ? 1 : 0.7), lineWidth: (isSelected ? 2 : 1) * point)
                // Small text still gets a box big enough to tap
                .frame(width: max(frame.width + 6 * point, 24 * point), height: max(frame.height + 6 * point, 24 * point))
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

/// How far the photo is zoomed in and moved, kept between gestures.
private struct Zoom {
    static let most: CGFloat = 6

    var scale: CGFloat = 1
    var offset = CGSize.zero
    /// Where the current gesture started from.
    private var startScale: CGFloat = 1
    private var startOffset = CGSize.zero

    mutating func pinch(by magnification: CGFloat) {
        scale = min(max(startScale * magnification, 1), Self.most)
    }

    mutating func drag(by translation: CGSize) {
        guard scale > 1 else { return }
        offset = CGSize(width: startOffset.width + translation.width, height: startOffset.height + translation.height)
    }

    /// At the end of a gesture: back to fitting at all but a zoom, and
    /// moved no further than keeps the photo's edges on screen.
    mutating func settle(fitting size: CGSize) {
        let spareWidth = size.width * (scale - 1) / 2
        let spareHeight = size.height * (scale - 1) / 2
        offset = CGSize(
            width: min(max(offset.width, -spareWidth), spareWidth),
            height: min(max(offset.height, -spareHeight), spareHeight))
        startScale = scale
        startOffset = offset
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
    /// The line picked, if any: tiles it can't fill are dimmed.
    let line: String?
    /// The field waiting for a line, if any.
    let chosen: BagField?
    let today: String
    let onTap: (BagField) -> Void

    var body: some View {
        let likely = line.map { BagLabel.likelyFields(in: $0, today: today) } ?? []
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(BagField.allCases, id: \.self) { field in
                let fits = line.map { BagLabel.value(in: $0, for: field, today: today) != nil } ?? true
                Button {
                    onTap(field)
                } label: {
                    tile(field, isLikely: likely.contains(field))
                        .overlay {
                            if chosen == field {
                                RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, lineWidth: 2.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(!fits)
                .opacity(fits ? 1 : 0.4)
                .accessibilityAddTraits(chosen == field ? .isSelected : [])
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
