import CoffeeCore
import SwiftUI

/// The bean queue in the order the scheduler will use it, plus frozen bags.
/// Finished bags aren't listed; BeanConqueror is the place to look back.
/// Edit mode drags bags into a manual order (like the web app's drag to
/// reorder); swipe a bag to freeze or thaw it, or back to automatic order.
struct BeansView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingFreeze: Bean?

    var body: some View {
        let queue = model.activeBeans.filter { !$0.isFrozen }
        NavigationStack {
            List {
                Section {
                    ForEach(queue) { bean in
                        row(bean)
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
                } header: {
                    Text("Queue")
                } footer: {
                    if !queue.isEmpty {
                        Text("Tap Edit to drag bags into the order you'll drink them. Numbered bags are in that order; the rest follow, in-progress first, then by ready date.")
                    }
                }
                let frozen = model.activeBeans.filter(\.isFrozen)
                if !frozen.isEmpty {
                    Section("Frozen") {
                        ForEach(frozen) { bean in
                            row(bean)
                                .swipeActions { FreezeSwipeButton(bean: bean, confirming: $confirmingFreeze) }
                        }
                    }
                }
            }
            .navigationTitle("Beans")
            .navigationDestination(for: BeanRoute.self) { BeanDetailView(beanID: $0.id) }
            .freezeConfirmation(for: $confirmingFreeze)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                if queue.contains(where: { $0.displayOrder != nil }) {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Use automatic order", systemImage: "arrow.uturn.backward") {
                                model.clearQueueOrder()
                            }
                        } label: {
                            Label("Queue order", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    private func row(_ bean: Bean) -> some View {
        NavigationLink(value: BeanRoute(id: bean.id)) {
            BeanRow(bean: bean, today: model.today)
        }
    }
}

private struct BeanRow: View {
    @Environment(AppModel.self) private var model
    let bean: Bean
    let today: String

    var body: some View {
        HStack(spacing: 10) {
            RoasterRail(color: model.rail(bean.roaster), height: 40)
            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let order = bean.displayOrder, !bean.isFrozen {
                    Text("\(order)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Position \(order)")
                }
                Text(bean.name).font(.headline)
            }
            if !bean.roaster.isEmpty {
                Text(bean.roaster).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text("\(Format.grams(max(0, bean.remainingGrams)))g left")
                // A frozen bag's thaw date matters more than its ready date
                if bean.isFrozen {
                    Text(bean.plannedThawDate.map { "Thaws \(Format.shortDay($0))" } ?? "No thaw date")
                        .foregroundStyle(.cyan)
                } else if let ready = bean.readyDate {
                    Text(ready <= today ? "Ready" : "Ready \(Format.shortDay(ready))")
                        .foregroundStyle(ready <= today ? Color.green : Color.secondary)
                }
                // Age at first and last cup says more than the roast date;
                // a bag that isn't scheduled has only the roast date.
                if let ages = model.ageRanges[bean.id] {
                    Text("Age \(Format.ages(ages))")
                        .foregroundStyle(ages.finish > BeanDetail.oldFinishAge ? Color.red : Color.secondary)
                } else if let roast = bean.roastDate {
                    Text("Roasted \(Format.shortDay(roast))").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(1)
        }
    }
}
