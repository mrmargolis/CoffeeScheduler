import SwiftUI

/// The app's one look: warm and dark, taken from the app icon. There is no
/// light variant, so these are fixed colours rather than adaptive ones.
enum Theme {
    /// Screen background.
    static let ground = Color(hex: "#15110D")
    static let card = Color(hex: "#201910")
    /// Chips, stepper wells and round buttons on a card.
    static let raised = Color(hex: "#2A2117")
    /// Dividers inside cards.
    static let hairline = Color(hex: "#382C1F")

    static let text = Color(hex: "#F4ECDD")
    static let text2 = Color(hex: "#BBAA92")
    /// Section labels.
    static let text3 = Color(hex: "#94836C")
    /// Dates outside the month and dashed outlines.
    static let dim = Color(hex: "#6E5F4C")

    /// Gold: the selected tab, today, links and early-start notes.
    static let accent = Color(hex: "#E0AA45")
    static let frozen = Color(hex: "#6FC3D6")
    static let gap = Color(hex: "#E5766A")
    static let gapText = Color(hex: "#F0A096")
    static let ready = Color(hex: "#9AD493")

    /// Corner radius of a tile inside a card.
    static let tileRadius: CGFloat = 18
    static let dash = StrokeStyle(lineWidth: 1, dash: [4, 3])
}

extension View {
    /// The whole app: dark, with the gold tint.
    func coffeeTheme() -> some View {
        tint(Theme.accent).preferredColorScheme(.dark)
    }

    /// The ground behind a List or Form. Rows take `Theme.card` separately,
    /// since a row background is set from inside the list.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.ground)
            .foregroundStyle(Theme.text)
    }

    /// Keeps scrolled content from showing behind the status bar on a
    /// screen that hides its navigation bar.
    func statusBarCover() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0).background(Theme.ground)
        }
    }
}

/// The top of a tab's screen: a small gold line over the title.
struct ScreenHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.footnote.weight(.semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A section's small uppercase label, with an optional detail at the far edge.
struct SectionLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .tracking(0.8)
                .textCase(.uppercase)
            Spacer()
            if let detail {
                Text(detail).font(.caption).monospacedDigit().textCase(nil)
            }
        }
        .foregroundStyle(Theme.text3)
    }
}

/// A list row's card. Today's row and a collapsed run of days draw a tile
/// inside it.
struct RowCard: View {
    enum Tile { case none, today, skipped, gap }
    var tile = Tile.none

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tileRadius)
        ZStack {
            Theme.card
            switch tile {
            case .none: EmptyView()
            case .today: shape.fill(Theme.accent.opacity(0.16)).padding(4)
            case .skipped: shape.strokeBorder(Theme.dim, style: Theme.dash).padding(4)
            case .gap:
                shape.fill(Theme.gap.opacity(0.12))
                    .overlay(shape.strokeBorder(Theme.gap, style: Theme.dash))
                    .padding(4)
            }
        }
    }
}
