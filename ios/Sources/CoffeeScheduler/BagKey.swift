import CoffeeCore
import SwiftUI

/// Which bag runs over which dates, in the order they're drunk. Tapping a
/// bag opens it.
struct BagKey: View {
    @Environment(AppModel.self) private var model
    let runs: [BagRun]
    let openBean: (String) -> Void

    var body: some View {
        let early = daysEarly
        ForEach(runs, id: \.beanID) { run in
            Button {
                openBean(run.beanID)
            } label: {
                row(run, status: status(run, daysEarly: early[run.beanID]))
            }
            .buttonStyle(.plain)
        }
    }

    private func row(_ run: BagRun, status: Status) -> some View {
        HStack(spacing: 12) {
            Circle().fill(model.rail(run.roaster)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(run.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(run.roaster.isEmpty ? status.text : "\(run.roaster) · \(status.text)")
                    .font(.caption)
                    .foregroundStyle(status.isEarly ? Theme.accent : Theme.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.span(run.start, run.end)).font(.footnote.weight(.semibold))
                if let ages = model.ageRanges[run.beanID] {
                    Text(Format.ages(ages))
                        .font(.caption)
                        .foregroundStyle(ages.finish > BeanDetail.oldFinishAge ? Theme.gapText : Theme.text2)
                        .accessibilityLabel("Age \(Format.ages(ages))")
                }
            }
            .monospacedDigit()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private struct Status {
        let text: String
        var isEarly = false
    }

    /// What the bag is up to, in a word or two after its roaster.
    private func status(_ run: BagRun, daysEarly: Int?) -> Status {
        if let bean = model.activeBeans.first(where: { $0.id == run.beanID }), bean.isFrozen {
            return Status(text: bean.plannedThawDate.map { "thaws \(Format.shortDay($0))" } ?? "frozen")
        }
        if run.end < model.today { return Status(text: "finished") }
        if run.start <= model.today { return Status(text: "on the grinder") }
        if let daysEarly { return Status(text: "\(Format.days(daysEarly)) early", isEarly: true) }
        return Status(text: "\(Format.grams(run.grams.rounded())) g")
    }

    /// How many days before its ready date each early bag starts.
    private var daysEarly: [String: Int] {
        var result: [String: Int] = [:]
        for day in model.schedule {
            for cup in day.consumptions where result[cup.beanID] == nil {
                if let early = cup.daysEarly, early > 0 { result[cup.beanID] = early }
            }
        }
        return result
    }
}
