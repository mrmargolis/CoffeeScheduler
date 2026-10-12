import CoffeeCore
import SwiftUI

/// Navigation value for opening a bag's detail screen.
struct BeanRoute: Hashable {
    let id: String
}

/// One bag: how much is left, how old it is, when it's scheduled, and its
/// history. Edit opens `BeanSettingsForm`,
/// and the Freeze/Thaw button asks first.
struct BeanDetailView: View {
    @Environment(AppModel.self) private var model
    let beanID: String
    @State private var editing = false
    @State private var confirmingFreeze: Bean?

    var body: some View {
        if let detail = model.detail(forBean: beanID) {
            content(detail)
                .navigationTitle(detail.bean.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // The name is the screen's own heading, so the bar doesn't repeat it
                    ToolbarItem(placement: .principal) {
                        Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                    }
                    if !detail.bean.archived {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Edit") { editing = true }
                        }
                    }
                }
                .sheet(isPresented: $editing) {
                    NavigationStack {
                        BeanSettingsForm(bean: detail.bean, today: model.today)
                    }
                }
                .freezeConfirmation(for: $confirmingFreeze)
        } else {
            ContentUnavailableView("Bag not found", systemImage: "questionmark.circle")
        }
    }

    private func content(_ detail: BeanDetail) -> some View {
        let bean = detail.bean
        let color = model.rail(bean.roaster)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BagHeader(detail: detail, color: color)
                RemainingCard(detail: detail, color: color)
                if let track = detail.ageTrack, let roast = bean.roastDate, let ready = bean.readyDate {
                    AgeCard(detail: detail, track: track, roast: roast, ready: ready, color: color)
                }
                BagFacts(bean: bean, today: model.today, restSource: restSource(bean))
                if !bean.archived {
                    FreezeButton(isFrozen: bean.isFrozen) { confirmingFreeze = bean }
                }
                BagHistory(history: model.history(forBean: beanID))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .foregroundStyle(Theme.text)
    }

    /// Where the bag's rest days come from.
    private func restSource(_ bean: Bean) -> String {
        if bean.restDays != nil { return "Set on this bag" }
        return model.roasterDefaults.contains { $0.roaster == bean.roaster } ? "Roaster default" : "Default rest"
    }
}

/// Roaster, name, origin and flavour notes.
private struct BagHeader: View {
    let detail: BeanDetail
    let color: Color

    var body: some View {
        let bean = detail.bean
        VStack(alignment: .leading, spacing: 8) {
            if !bean.roaster.isEmpty {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 10, height: 10)
                    Text(bean.roaster)
                        .font(.footnote.weight(.semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.text2)
                }
            }
            Text(bean.name).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            if !detail.provenance.isEmpty {
                Text(detail.provenance).font(.subheadline).foregroundStyle(Theme.text2)
            }
            let notes = Self.notes(bean.flavourProfile)
            if !notes.isEmpty || bean.isFrozen || bean.archived {
                FlowLayout(spacing: 6) {
                    if bean.archived {
                        Badge(text: "Finished", color: Theme.text2, background: Theme.raised)
                    } else if bean.isFrozen {
                        Badge(text: "Frozen", color: Theme.frozenText, background: Theme.frozen.opacity(0.18))
                    }
                    ForEach(notes, id: \.self) { note in
                        Badge(text: note, color: Theme.text, background: Theme.raised)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 8)
    }

    /// "Red apple, panela" as separate notes.
    static func notes(_ flavour: String?) -> [String] {
        (flavour ?? "")
            .split(whereSeparator: { ",;/".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// How much is left, as a large figure over a bar, and when it's scheduled.
private struct RemainingCard: View {
    let detail: BeanDetail
    let color: Color

    var body: some View {
        let bean = detail.bean
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.grams(max(0, bean.remainingGrams).rounded()))
                    .font(.system(size: 40, weight: .bold))
                Text("g of \(Format.grams(bean.weightGrams)) left")
                    .font(.subheadline)
                    .foregroundStyle(Theme.text2)
                Spacer(minLength: 8)
                if let days = detail.daysLeft {
                    Text("about \(Format.days(days))").font(.footnote).foregroundStyle(Theme.text2)
                }
            }
            MeterBar(fraction: 1 - detail.fractionConsumed, color: color, height: 8)
            HStack(spacing: 4) {
                Text(detail.consumedGrams > 0 ? "\(Format.grams(bean.totalBrewedGrams.rounded())) g brewed" : "Unopened")
                Spacer(minLength: 8)
                if let start = detail.start, let finish = detail.finish {
                    Text("Scheduled")
                    Text(Format.span(start, finish)).fontWeight(.semibold).foregroundStyle(Theme.text)
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.text2)
        }
        .monospacedDigit()
        .lineLimit(1)
        .cardBackground(Theme.card)
    }
}

/// The bag's settings and dates, two tiles to a row.
private struct BagFacts: View {
    let bean: Bean
    let today: String
    let restSource: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            FactTile(label: "Rest required", value: Format.days(bean.effectiveRestDays), note: restSource)
            if let ready = bean.readyDate {
                let wait = DateUtils.daysBetween(today, ready)
                FactTile(
                    label: wait > 0 ? "Ready" : "Ready since", value: Format.shortDay(ready),
                    note: wait > 0 ? "in \(Format.days(wait))" : "Rested"
                )
            } else {
                FactTile(label: "Ready", value: "Unknown", note: "No roast date", isWarning: true)
            }
            if !bean.isFrozen, let grams = bean.freezeAfterGrams {
                FactTile(label: "Freeze after", value: "\(Format.grams(grams)) g", note: "brewed, then frozen")
            }
            if bean.isFrozen, let thaw = bean.plannedThawDate {
                FactTile(label: "Planned thaw", value: Format.shortDay(thaw), note: "Back in the schedule")
            }
        }
    }
}

private struct FactTile: View {
    let label: String
    let value: String
    let note: String
    var isWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text3)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(note).font(.caption).foregroundStyle(isWarning ? Theme.accent : Theme.text2)
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.tileRadius))
    }
}

/// Outlined, cool for a freeze and gold for a thaw.
private struct FreezeButton: View {
    let isFrozen: Bool
    let action: () -> Void

    var body: some View {
        let color = isFrozen ? Theme.accent : Theme.frozen
        let shape = RoundedRectangle(cornerRadius: Theme.tileRadius)
        Button(action: action) {
            Label(isFrozen ? "Thaw bag" : "Freeze bag", systemImage: isFrozen ? "sun.max" : "snowflake")
                .font(.callout.weight(.semibold))
                .foregroundStyle(isFrozen ? Theme.accent : Theme.frozenText)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(shape.fill(color.opacity(0.1)))
                .overlay(shape.strokeBorder(color.opacity(0.5), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
