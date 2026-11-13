import CoffeeCore
import SwiftUI

extension QueuePart where B == Bean {
    /// The rest of a bag drunk to its break, and not yet back.
    var isOnBreak: Bool { isRest && !isStarted }
}

extension AppModel {
    /// Opened and in the schedule by today; a bag due to start today isn't
    /// yet, and one on a break isn't until it's taken up again.
    func isOnGrinder(_ part: QueuePart<Bean>) -> Bool {
        let bean = part.bean
        guard bean.remainingGrams < bean.weightGrams, !part.isOnBreak else { return false }
        return part.isRest || (partRuns[part.id].map { $0.start <= today } ?? false)
    }
}

/// A bag or rest while the queue is reordered: one line each, so the whole
/// queue fits on the screen and long names have room.
struct ReorderRow: View {
    @Environment(AppModel.self) private var model
    let part: QueuePart<Bean>
    /// The bag's own card, rather than the rest after a break.
    let isBag: Bool

    private var start: String? { model.partRuns[part.id]?.start }

    var body: some View {
        let color = model.rail(part.bean.roaster)
        let shape = RoundedRectangle(cornerRadius: Theme.tileRadius)
        HStack(spacing: 12) {
            if isBag {
                QueueTile(order: part.displayOrder, color: color, isSolid: model.isOnGrinder(part), size: 32)
            } else {
                RestTile(order: part.displayOrder, color: color, size: 32)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(part.bean.name).font(.headline.bold()).lineLimit(1)
                status.font(.footnote).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(height: 60)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card.opacity(isBag ? 1 : 0.45), in: shape)
        .overlay {
            if !isBag { shape.strokeBorder(color.opacity(0.7), style: Theme.dash) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Square Mile · on the grinder", "Square Mile · starts Oct 22", or for
    /// a rest, "Rest after 100 g · back Oct 30".
    private var status: Text {
        let back = start.map { " · back \(Format.shortDay($0))" } ?? ""
        if !isBag { return Text("Rest after \(Format.grams(part.startGrams)) g" + back) }
        let roaster = part.bean.roaster.isEmpty ? "" : "\(part.bean.roaster) · "
        if model.isOnGrinder(part) { return Text(roaster) + Text("on the grinder").foregroundStyle(Theme.accent) }
        if part.isOnBreak { return Text(roaster + "on a break" + back) }
        if let start { return Text(roaster + "starts \(Format.shortDay(start))") }
        return Text(part.bean.roaster.isEmpty ? "Not scheduled" : "\(part.bean.roaster) · not scheduled")
    }
}

/// The queue's rules, folded away under one row: read once, not scrolled
/// past every day.
struct QueueHelp: View {
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text("How the queue works")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.dim)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(.subheadline)
                .foregroundStyle(Theme.text3)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Shown" : "Hidden")
            if isExpanded {
                Text(
                    """
                    Numbered bags are in the order you set; the rest follow, in-progress first, then by ready date. \
                    Swipe a bag left to freeze it or take a break, or right to hand it back to automatic order. \
                    A break leaves the rest of the bag as a dashed card: drag it to choose when you come back to it. \
                    A gold hourglass marks a bag due to start before the shorter of its own and its roaster's rest.
                    """
                )
                .font(.footnote)
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }
}
