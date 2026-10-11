import CoffeeCore
import SwiftUI

/// The bean queue in the order the scheduler will use it, plus finished bags.
struct BeansView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section("Queue") {
                    ForEach(model.activeBeans.filter { !$0.isFrozen }) { bean in
                        BeanRow(bean: bean, today: model.today)
                    }
                }
                let frozen = model.activeBeans.filter(\.isFrozen)
                if !frozen.isEmpty {
                    Section("Frozen") {
                        ForEach(frozen) { bean in
                            BeanRow(bean: bean, today: model.today)
                        }
                    }
                }
                if !model.archivedBeans.isEmpty {
                    Section("Finished") {
                        ForEach(model.archivedBeans) { bean in
                            BeanRow(bean: bean, today: model.today)
                        }
                    }
                }
            }
            .navigationTitle("Beans")
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
                if let ready = bean.readyDate, !bean.archived {
                    Text(ready <= today ? "Ready" : "Ready \(Format.shortDay(ready))")
                        .foregroundStyle(ready <= today ? Color.green : Color.secondary)
                }
                if let thaw = bean.plannedThawDate, bean.isFrozen {
                    Text("Thaws \(Format.shortDay(thaw))")
                }
                if let roast = bean.roastDate {
                    Text("Roasted \(Format.shortDay(roast))").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }
}
