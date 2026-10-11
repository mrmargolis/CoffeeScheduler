import CoffeeCore
import SwiftUI

/// The bag's age today, its life from roast to last cup as a bar, and the
/// age at its first and last cup.
struct AgeCard: View {
    let detail: BeanDetail
    let track: BeanDetail.AgeTrack
    let roast: String
    let ready: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                SectionLabel(title: "Age")
                if let age = detail.currentAge {
                    let frozen = detail.bean.frozenDaysToDate
                    Text(Format.days(age)).fontWeight(.bold)
                    Text(frozen > 0 ? "today · \(frozen) frozen" : "today").foregroundStyle(Theme.text2)
                }
            }
            .font(.footnote)
            AgeBar(track: track, color: color)
            HStack(alignment: .top) {
                Fact(label: "Roasted", value: Format.shortDay(roast))
                Spacer()
                // Without a scheduled run, the rest date stands in for the first cup
                if let startAge = detail.startAge {
                    Fact(label: "First cup", value: "Day \(startAge)", alignment: .center)
                } else {
                    Fact(label: "Rested", value: Format.shortDay(ready), alignment: .center)
                }
                Spacer()
                if let finishAge = detail.finishAge {
                    Fact(
                        label: "Last cup", value: "Day \(finishAge)", alignment: .trailing,
                        isWarning: finishAge > BeanDetail.oldFinishAge
                    )
                }
            }
        }
        .monospacedDigit()
        .cardBackground(Theme.card)
    }
}

private struct Fact: View {
    let label: String
    let value: String
    var alignment = HorizontalAlignment.leading
    var isWarning = false

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text3)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(isWarning ? Theme.gapText : Theme.text)
        }
    }
}

/// Roast → ready (resting, muted) → last cup (the roaster's colour) along
/// the bag's life, with a gold tick at today.
private struct AgeBar: View {
    let track: BeanDetail.AgeTrack
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let rest = width * track.restFraction
            let now = width * track.todayFraction
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline).frame(height: 6)
                Capsule().fill(color).frame(height: 6).padding(.leading, min(rest, width))
                Capsule().fill(Theme.dim).frame(width: rest, height: 6)
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.accent)
                    .frame(width: 3, height: 22)
                    .offset(x: min(max(0, now - 1.5), width - 3))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 26)
        .accessibilityElement()
        .accessibilityLabel("Age")
        .accessibilityValue("\(Int(track.todayFraction * 100)) percent of the way from roast to last cup")
    }
}

/// The latest brews and the freezer history, each only when there is any.
struct BagHistory: View {
    let history: AppModel.BeanHistory

    var body: some View {
        if !history.recentBrews.isEmpty {
            section("Recent brews") {
                ForEach(Array(history.recentBrews.enumerated()), id: \.offset) { index, brew in
                    row(isFirst: index == 0) {
                        Text(Format.shortDay(brew.creationDate)).foregroundStyle(Theme.text2)
                        Text("\(Format.grams(brew.groundCoffeeGrams)) g")
                        Spacer()
                        if let rating = brew.rating {
                            Text("★ \(Format.grams(rating))").foregroundStyle(Theme.accent)
                        } else {
                            Text("—").foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
        }

        if !history.freezeEvents.isEmpty {
            section("Freezer history") {
                ForEach(Array(history.freezeEvents.enumerated()), id: \.offset) { index, event in
                    row(isFirst: index == 0) {
                        Circle().fill(event.kind == .freeze ? Theme.frozen : Theme.accent).frame(width: 8, height: 8)
                        Text(event.kind == .freeze ? "Frozen" : "Thawed")
                        Spacer()
                        Text(Format.mediumDay(event.date)).font(.footnote).foregroundStyle(Theme.text2)
                    }
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: title).padding(.horizontal, 4).padding(.top, 2)
            VStack(spacing: 0) { rows() }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }

    private func row(isFirst: Bool, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            if !isFirst { Theme.hairline.frame(height: 1) }
            HStack(spacing: 12) { content() }
                .font(.subheadline)
                .monospacedDigit()
                .frame(minHeight: 48)
        }
    }
}

/// Lays views out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for (subview, origin) in zip(subviews, rows.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private struct Rows {
        var origins: [CGPoint] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> Rows {
        var rows = Rows()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rows.origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            rows.width = max(rows.width, x - spacing)
        }
        rows.height = y + rowHeight
        return rows
    }
}
