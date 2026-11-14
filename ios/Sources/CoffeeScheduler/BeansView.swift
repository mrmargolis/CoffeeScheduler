import CoffeeCore
import SwiftUI

/// The bean queue in the order the scheduler will use it, plus frozen bags,
/// a card per bag, and one for the rest of a bag after each break. Finished
/// bags aren't listed; BeanConqueror is the place to look back. Reorder drags
/// bags and rests into a manual order; swipe a bag to freeze or thaw it,
/// take a break from it, or put it back in automatic order.
struct BeansView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingFreeze: Bean?
    @State private var path: [BeanRoute] = []
    @State private var editMode: EditMode
    @State private var addingBag = false
    @State private var breaking: BreakDraft?
    @State private var showingHelp = false

    /// Taps on the Beans tab while it's showing: see `scrollsToTop`.
    let retaps: Int

    init(reordering: Bool = false, retaps: Int = 0) {
        _editMode = State(initialValue: reordering ? .active : .inactive)
        self.retaps = retaps
    }

    var body: some View {
        let queue = model.activeBeans.filter { !$0.isFrozen }
        let frozen = model.activeBeans.filter(\.isFrozen)
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                List {
                    Group {
                        header(queue: queue, frozen: frozen).id(ScrollTop.id)
                        HStack(spacing: 0) {
                            SectionLabel(title: "Queue")
                            // A picture of the queue and freezer to post
                            if !model.activeBeans.isEmpty { ShareBeansLink().padding(.vertical, -12) }
                        }
                        .padding(.horizontal, 4)
                        if isReordering {
                            note("Drag to set the order the schedule drinks them in. A dashed row is the rest of a bag after its break.")
                        }
                        queueRows(model.queue)
                        if queue.isEmpty {
                            note("No bags in the queue. Import a BeanConqueror export from Settings.")
                        } else if !isReordering {
                            QueueHelp(isExpanded: $showingHelp)
                        }
                        if !frozen.isEmpty {
                            SectionLabel(title: "Frozen").padding(.horizontal, 4).padding(.top, 6)
                            if isReordering {
                                note("Frozen bags join the queue when they thaw.")
                            } else {
                                ForEach(frozen) { bean in
                                    open(bean) { FrozenCard(bean: bean) }
                                        .swipeActions { FreezeSwipeButton(bean: bean, confirming: $confirmingFreeze) }
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollsToTop(on: retaps, path: $path, proxy: proxy)
            }
            .environment(\.editMode, $editMode)
            .themedList()
            .statusBarCover()
            // The title is drawn in the list; this one names the back button
            .navigationTitle("Beans")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: BeanRoute.self) { BeanDetailView(beanID: $0.id) }
            .freezeConfirmation(for: $confirmingFreeze)
            .breakDialog($breaking)
            .fullScreenCover(isPresented: $addingBag) { AddBagView() }
        }
    }

    private var isReordering: Bool { editMode == .active }

    private func header(queue: [Bean], frozen: [Bean]) -> some View {
        var counts = ["\(queue.count) in the queue"]
        if !frozen.isEmpty { counts.append("\(frozen.count) frozen") }
        return ScreenHeader(eyebrow: counts.joined(separator: " · "), title: "Beans") {
            if isReordering && model.queue.contains(where: { $0.displayOrder != nil }) {
                PillButton(title: "Reset order") { model.clearQueueOrder() }
                    .accessibilityHint("Puts the queue back in automatic order")
            }
            if !isReordering {
                PillButton(title: "Add a bag") { addingBag = true }
                    .accessibilityHint("Fills in a bag from photos of it, its page or by hand, to add to BeanConqueror")
            }
            if model.queue.count > 1 {
                PillButton(title: isReordering ? "Done" : "Reorder", isProminent: isReordering) {
                    withAnimation { editMode = isReordering ? .inactive : .active }
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 9)
    }

    /// A card for each bag at the place of the part it's in, and one for
    /// the rest of it after each break.
    private func queueRows(_ queue: [QueuePart<Bean>]) -> some View {
        let shown = Dictionary(queue.map { ($0.bean.id, $0.id) }) { first, _ in first }
        return ForEach(queue) { part in
            let isBag = shown[part.bean.id] == part.id
            open(part.bean) {
                if isReordering {
                    ReorderRow(part: part, isBag: isBag)
                } else if isBag {
                    QueueCard(part: part)
                } else {
                    RestCard(part: part)
                }
            }
            .swipeActions { swipeActions(part, isBag: isBag) }
            .swipeActions(edge: .leading) {
                if part.displayOrder != nil {
                    Button {
                        model.clearQueueOrder(id: part.id)
                    } label: {
                        Label("Auto order", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.gray)
                }
            }
        }
        .onMove { from, to in
            var ids = queue.map(\.id)
            let moved = from.map { ids[$0] }
            ids.move(fromOffsets: from, toOffset: to)
            // A rest dragged above its bag goes just below it
            ids = Scheduler.keepingPartsInOrder(ids, parts: queue)
            // The lowest of the moved rows, so every one of them keeps its place
            if let last = ids.last(where: moved.contains) { model.moveInQueue(ids, moved: last) }
        }
    }

    /// A bag's card freezes it or takes a break, and on a break, ends it; a
    /// rest's moves or ends its break.
    @ViewBuilder
    private func swipeActions(_ part: QueuePart<Bean>, isBag: Bool) -> some View {
        if isBag {
            FreezeSwipeButton(bean: part.bean, confirming: $confirmingFreeze)
            Button("Break", systemImage: "pause.circle") { breaking = .new(for: part.bean) }
                .tint(.indigo)
        }
        if let pause = part.after, !isBag || !part.isStarted {
            Button(isBag ? "Back now" : "End break", systemImage: "play.circle") { model.endBreak(id: pause.id) }
                .tint(Theme.accent)
        }
        if !isBag, let draft = BreakDraft.moving(part) {
            Button("Change", systemImage: "slider.horizontal.3") { breaking = draft }
                .tint(.gray)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
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
/// Filled in gold while it ends a mode, like Done.
private struct PillButton: View {
    let title: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isProminent ? .bold : .semibold))
                .foregroundStyle(isProminent ? Theme.ground : Theme.accent)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(isProminent ? Theme.accent : Theme.card, in: Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}
