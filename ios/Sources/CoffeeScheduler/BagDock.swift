import CoffeeCore
import SwiftUI

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

/// What the bar at the bottom of Add a bag does.
struct BagDockActions {
    let takePhoto: () -> Void
    let choosePhoto: () -> Void
    let search: (BagSearch) -> Void
    let add: () -> Void
}

/// Pinned under Add a bag, in reach wherever the form is scrolled to: what
/// the last photo or page did, the four ways to fill the bag in, and Add.
struct BagDock: View {
    let intake: BagIntake
    let actions: BagDockActions

    var body: some View {
        VStack(spacing: 10) {
            status
            HStack(spacing: 8) {
                source("Camera", "camera", action: actions.takePhoto)
                source("Photos", "photo.on.rectangle", action: actions.choosePhoto)
                source("Google", "magnifyingglass") { actions.search(.google) }
                source("Bean Base", "list.bullet.rectangle") { actions.search(.beanBase) }
            }
            .disabled(intake.status == .reading)
            Button(action: actions.add) {
                Label("Add to BeanConqueror", systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(canAdd ? Theme.ground : Theme.text3)
            .disabled(!canAdd)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.card)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var canAdd: Bool {
        intake.status != .reading && BeanConquerorLink.url(for: intake.draft) != nil
    }

    private func source(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.body)
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.borderless)
    }

    private var status: some View {
        HStack(spacing: 8) {
            message.font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            if intake.canUndo, intake.status != .reading {
                Button("Undo", action: intake.undo)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Take back \(intake.lastSourceName)")
            }
        }
    }

    @ViewBuilder private var message: some View {
        switch intake.status {
        case .reading:
            HStack(spacing: 6) {
                ProgressView()
                Text("Reading…")
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.gapText)
        case .filled(let message):
            Text(message).foregroundStyle(Theme.text2)
        case .ready:
            Text(
                intake.draft.has(.coffee)
                    ? "Opens BeanConqueror's Add bean screen with these filled in, to check and save there."
                    : "Add needs at least the coffee's name."
            )
            .foregroundStyle(Theme.text3)
        }
    }
}
