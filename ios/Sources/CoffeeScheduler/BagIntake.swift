import CoffeeCore
import SwiftUI
import UIKit

/// A photo or page the bag being added was filled in from.
struct BagSource: Identifiable {
    enum Kind: Equatable {
        /// A photo of the label, the right way up and no bigger than it needs
        /// to be, and the lines read off it, top to bottom.
        case photo(UIImage, lines: [BagLabel.Line])
        /// The coffee's page, by its site, and its text a line at a time.
        case page(host: String, lines: [String])
    }

    let id = UUID()
    let kind: Kind

    var isPhoto: Bool {
        if case .photo = kind { true } else { false }
    }

    /// The icon a field filled from it shows.
    var symbol: String { isPhoto ? "camera" : "globe" }

    /// Its text, a line at a time, top to bottom.
    var lines: [String] {
        switch kind {
        case .photo(_, let lines): lines.map(\.text)
        case .page(_, let lines): lines
        }
    }
}

/// Where Add a bag is with reading a photo or page, for the line over Add.
enum ScanStatus: Equatable {
    case reading
    case ready
    /// What the last photo or page did, or that the bag went to BeanConqueror.
    case filled(String)
    case failed(String)
}

/// The bag being added and how it got that way: the photos and pages used,
/// which source each field came from, and what the last one changed, so it
/// can be undone or a value it replaced put back.
@MainActor
@Observable
final class BagIntake {
    var draft = BagDraft()
    private(set) var sources: [BagSource] = []
    var status = ScanStatus.ready
    /// What the last photo or page did, for the gold dots and Keep buttons.
    private(set) var lastFill: BagFill?
    private(set) var lastSourceName = ""
    /// The source each field's value came from; none once it's typed.
    private(set) var fieldSources: [BagField: BagSource] = [:]
    private var undoState: Snapshot?

    private struct Snapshot {
        let draft: BagDraft
        let sources: [BagSource]
        let fieldSources: [BagField: BagSource]
    }

    var isEmpty: Bool { draft == BagDraft() && sources.isEmpty }
    var canUndo: Bool { undoState != nil }
    var photos: [BagSource] { sources.filter(\.isPhoto) }

    /// "photo 2", "the page": how the status line names the next source.
    func name(for kind: BagSource.Kind) -> String {
        switch kind {
        case .photo:
            let count = photos.count + 1
            return count == 1 ? "the photo" : "photo \(count)"
        case .page(let host, _):
            return host
        }
    }

    /// Merges what a photo or page found, and says what changed.
    func fill(_ found: BagDraft, from kind: BagSource.Kind) {
        let source = BagSource(kind: kind)
        let name = name(for: kind)
        undoState = Snapshot(draft: draft, sources: sources, fieldSources: fieldSources)
        let (merged, fill) = draft.filling(with: found)
        draft = merged
        sources.append(source)
        for field in fill.filled + fill.replaced.map(\.field) { fieldSources[field] = source }
        lastFill = fill
        lastSourceName = name
        status = .filled(fill.summary(from: name))
    }

    /// Takes back the last photo or page.
    func undo() {
        guard let undoState else { return }
        draft = undoState.draft
        sources = undoState.sources
        fieldSources = undoState.fieldSources
        self.undoState = nil
        lastFill = nil
        status = .filled("Took back \(lastSourceName).")
    }

    /// Puts back the value a photo or page replaced, kept as if typed.
    func keep(_ replacement: BagFill.Replacement) {
        draft.restore(replacement.old, in: replacement.field)
        fieldSources[replacement.field] = nil
        lastFill?.replaced.removeAll { $0 == replacement }
    }

    /// Keeps a guess that's right, so the next photo or page can't replace it.
    func confirm(_ field: BagField) {
        draft.confirm(field)
        status = .filled("Kept the \(field.title.lowercased()). A photo or page won't replace it now.")
    }

    /// Text typed into a field, or a line of a label picked for it.
    func type(_ text: String, in field: BagField) {
        draft.type(text, in: field)
        fieldSources[field] = nil
    }

    /// A line of a photo or page picked for a field, kept as if typed.
    func pick(_ value: String, for field: BagField) {
        if field.text != nil { type(value, in: field) } else { set(field, to: value) }
        status = .filled("Put \(value) in \(field.title.lowercased()).")
    }

    /// The roast date or weight set by hand.
    func set(_ field: BagField, to text: String?) {
        draft.restore(text ?? "", in: field)
        fieldSources[field] = nil
    }

    func clear() {
        draft = BagDraft()
        sources = []
        fieldSources = [:]
        lastFill = nil
        undoState = nil
        status = .ready
    }
}
