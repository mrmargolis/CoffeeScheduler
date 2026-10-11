import CoffeeCore
import SwiftUI

/// The bean queue in the order the scheduler will use it, plus frozen bags,
/// a card per bag. Finished bags aren't listed; BeanConqueror is the place to
/// look back. Reorder drags bags into a manual order (like the web app's drag
/// to reorder); swipe a bag to freeze or thaw it, or back to automatic order.
struct BeansView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingFreeze: Bean?
    @State private var path: [BeanRoute] = []
    @State private var editMode: EditMode

    init(reordering: Bool = false) {
        _editMode = State(initialValue: reordering ? .active : .inactive)
    }

    var body: some View {
        let queue = model.activeBeans.filter { !$0.isFrozen }
        let frozen = model.activeBeans.filter(\.isFrozen)
        NavigationStack(path: $path) {
            List {
                Group {
                    header(queue: queue, frozen: frozen)
                    SectionLabel(title: "Queue").padding(.horizontal, 4)
                    queueRows(queue)
                    footer(isEmpty: queue.isEmpty)
                    if !frozen.isEmpty {
                        SectionLabel(title: "Frozen").padding(.horizontal, 4)
                        ForEach(frozen) { bean in
                            open(bean) { FrozenCard(bean: bean) }
                                .swipeActions { FreezeSwipeButton(bean: bean, confirming: $confirmingFreeze) }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
            .themedList()
            .statusBarCover()
            // The title is drawn in the list; this one names the back button
            .navigationTitle("Beans")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: BeanRoute.self) { BeanDetailView(beanID: $0.id) }
            .freezeConfirmation(for: $confirmingFreeze)
        }
    }

    private func header(queue: [Bean], frozen: [Bean]) -> some View {
        var counts = ["\(queue.count) in the queue"]
        if !frozen.isEmpty { counts.append("\(frozen.count) frozen") }
        let isReordering = editMode == .active
        return HStack(alignment: .bottom, spacing: 8) {
            ScreenHeader(eyebrow: counts.joined(separator: " · "), title: "Beans")
            if isReordering && queue.contains(where: { $0.displayOrder != nil }) {
                PillButton(title: "Automatic") { model.clearQueueOrder() }
                    .accessibilityLabel("Use automatic order")
            }
            if queue.count > 1 {
                PillButton(title: isReordering ? "Done" : "Reorder") {
                    withAnimation { editMode = isReordering ? .inactive : .active }
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 9)
    }

    private func queueRows(_ queue: [Bean]) -> some View {
        let starts = Scheduler.startDates(model.schedule)
        return ForEach(queue) { bean in
            open(bean) { QueueCard(bean: bean, start: starts[bean.id]) }
                .swipeActions { FreezeSwipeButton(bean: bean, confirming: $confirmingFreeze) }
                .swipeActions(edge: .leading) {
                    if bean.displayOrder != nil {
                        Button {
                            model.clearQueueOrder(id: bean.id)
                        } label: {
                            Label("Auto order", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.gray)
                    }
                }
        }
        .onMove { from, to in
            var ids = queue.map(\.id)
            ids.move(fromOffsets: from, toOffset: to)
            model.reorderQueue(ids)
        }
    }

    private func footer(isEmpty: Bool) -> some View {
        Text(
            isEmpty
                ? "No bags in the queue. Import a BeanConqueror export from Settings."
                : """
                Numbered bags are in the order you set; the rest follow, in-progress first, then by ready date. \
                Swipe a bag left to freeze it, or right to hand it back to automatic order.
                """
        )
        .font(.caption)
        .foregroundStyle(Theme.text3)
        .padding(.horizontal, 4)
    }

    /// A card that opens its bag. A button rather than a NavigationLink,
    /// which would add a chevron beside the card.
    private func open(_ bean: Bean, @ViewBuilder card: () -> some View) -> some View {
        Button {
            path.append(BeanRoute(id: bean.id))
        } label: {
            card()
        }
        .buttonStyle(.plain)
    }
}

/// A rounded text button on the ground, beside a screen's title.
private struct PillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Theme.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
