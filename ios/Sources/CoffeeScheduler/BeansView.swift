import CoffeeCore
import SwiftUI

/// The bean queue in the order the scheduler will use it, plus finished bags.
/// Swipe a bag to freeze or thaw it.
struct BeansView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingFreeze: Bean?

    var body: some View {
        NavigationStack {
            List {
                Section("Queue") {
                    ForEach(model.activeBeans.filter { !$0.isFrozen }) { bean in
                        row(bean)
                            .swipeActions { FreezeSwipeButton(bean: bean, confirming: $confirmingFreeze) }
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
                if !model.archivedBeans.isEmpty {
                    Section("Finished") {
                        ForEach(model.archivedBeans) { row($0) }
                    }
                }
            }
            .navigationTitle("Beans")
            .navigationDestination(for: BeanRoute.self) { BeanDetailView(beanID: $0.id) }
            .freezeConfirmation(for: $confirmingFreeze)
        }
    }

    private func row(_ bean: Bean) -> some View {
        NavigationLink(value: BeanRoute(id: bean.id)) {
            BeanRow(bean: bean, today: model.today)
        }
    }
}

private struct BeanRow: View {
    let bean: Bean
    let today: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bean.name).font(.headline)
            if !bean.roaster.isEmpty {
                Text(bean.roaster).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if !bean.archived {
                    Text("\(Format.grams(max(0, bean.remainingGrams)))g left")
                }
                // A frozen bag's thaw date matters more than its ready date
                if bean.isFrozen {
                    Text(bean.plannedThawDate.map { "Thaws \(Format.shortDay($0))" } ?? "No thaw date")
                        .foregroundStyle(.cyan)
                } else if let ready = bean.readyDate, !bean.archived {
                    Text(ready <= today ? "Ready" : "Ready \(Format.shortDay(ready))")
                        .foregroundStyle(ready <= today ? Color.green : Color.secondary)
                }
                if let roast = bean.roastDate {
                    Text("Roasted \(Format.shortDay(roast))").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(1)
        }
    }
}
