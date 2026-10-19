import CoffeeCore
import SwiftUI

/// Where the scan screen is with reading the bag, for the line under the
/// Add button.
enum ScanStatus: Equatable {
    case reading
    case ready
    /// What the last photo or page filled in.
    case filled(String)
    case failed(String)
}

/// The searches for the coffee's page: for the coffee and roaster when
/// there are any, else the search page itself.
enum BagSearch {
    case google
    case beanBase

    func url(for draft: BagDraft) -> URL {
        switch self {
        case .google: BagLabel.googleURL(for: draft.reading) ?? URL(string: "https://www.google.com")!
        case .beanBase: BagLabel.searchURL(for: draft.reading) ?? URL(string: BagLabel.searchPage)!
        }
    }
}

/// The bag being added: the ways to fill it in, every field editable, and
/// the button that hands it to BeanConqueror.
struct BagDraftForm: View {
    @Binding var draft: BagDraft
    /// The text read off the photos, in reading order.
    let labelText: [String]
    let status: ScanStatus
    let onAdd: () -> Void
    let onTakePhoto: () -> Void
    let onChoosePhoto: () -> Void
    let onSearch: (BagSearch) -> Void

    /// The text fields, for the rows and for "Use as" on a line of the label.
    private static var textFields: [(title: String, field: WritableKeyPath<BagDraft, String>)] {
        [
            ("Coffee", \.coffee), ("Roaster", \.roaster), ("Tasting notes", \.notes), ("Country", \.country),
            ("Region", \.region), ("Producer", \.producer), ("Variety", \.variety), ("Process", \.process),
        ]
    }

    var body: some View {
        Form {
            Group {
                fillSection
                Section {
                    BagTextRow(title: "Coffee", text: $draft.coffee)
                    BagTextRow(title: "Roaster", text: $draft.roaster)
                    RoastDateRow(date: $draft.roastDate)
                    WeightRow(grams: $draft.weightGrams)
                } header: {
                    SectionLabel(title: "Bag").listRowInsets(Theme.labelInsets)
                }
                Section {
                    ForEach(Self.textFields.dropFirst(2), id: \.title) { row in
                        BagTextRow(title: row.title, text: $draft[dynamicMember: row.field])
                    }
                    BagTextRow(title: "Link", text: $draft.url, prompt: "None")
                } header: {
                    SectionLabel(title: "Notes and origin").listRowInsets(Theme.labelInsets)
                }
                addSection
                if !labelText.isEmpty {
                    labelSection
                }
            }
            .listRowBackground(Theme.card)
            .listRowSeparatorTint(Theme.hairline)
        }
        .themedList()
    }

    private var addSection: some View {
        Section {
            Button(action: onAdd) {
                Label("Add to BeanConqueror", systemImage: "plus.circle.fill")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .disabled(status == .reading || BeanConquerorLink.url(for: draft) == nil)
        } footer: {
            footer.listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
        }
    }

    @ViewBuilder private var footer: some View {
        switch status {
        case .reading:
            HStack(spacing: 6) {
                ProgressView()
                Text("Reading…")
            }
            .font(.caption)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.gapText)
        case .filled(let message):
            Text(message).font(.caption).foregroundStyle(Theme.text3)
        case .ready:
            Text("Opens BeanConqueror's Add bean screen with these filled in, to check and save there.")
                .font(.caption)
                .foregroundStyle(Theme.text3)
        }
    }

    private var fillSection: some View {
        Section {
            Button("Take a photo of the bag", systemImage: "camera", action: onTakePhoto)
            Button("Choose a photo", systemImage: "photo.on.rectangle", action: onChoosePhoto)
            Button("Search Google", systemImage: "magnifyingglass") { onSearch(.google) }
            Button("Search Bean Base", systemImage: "list.bullet.rectangle") { onSearch(.beanBase) }
        } header: {
            SectionLabel(title: "Fill in from").listRowInsets(Theme.labelInsets)
        } footer: {
            SectionFooter(
                text: """
                    Or type it in below. Each photo, front or back, and each page you use fills in what's still \
                    empty; what's already there stays. On the coffee's page, tap Use this page.
                    """)
        }
        .disabled(status == .reading)
    }

    private var labelSection: some View {
        Section {
            ForEach(Array(labelText.enumerated()), id: \.offset) { _, line in
                Menu {
                    ForEach(Self.textFields, id: \.title) { row in
                        Button("Use as \(row.title.lowercased())") { draft[keyPath: row.field] = BagLabel.tidy(line) }
                    }
                } label: {
                    Text(line).foregroundStyle(Theme.text2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } header: {
            SectionLabel(title: "Text on the label").listRowInsets(Theme.labelInsets)
        } footer: {
            SectionFooter(text: "Tap a line to put it in a field.")
        }
    }
}
