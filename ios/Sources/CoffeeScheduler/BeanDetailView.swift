import CoffeeCore
import SwiftUI

/// Navigation value for opening a bag's detail screen.
struct BeanRoute: Hashable {
    let id: String
}

/// One bag: how much is left, how old it is, when it's scheduled, and its
/// history. Mirrors `src/components/BeanDetail.tsx`; Edit opens `BeanSettingsForm`,
/// and the Freeze/Thaw button asks first.
struct BeanDetailView: View {
    @Environment(AppModel.self) private var model
    let beanID: String
    @State private var editing = false
    @State private var confirmingFreeze: Bean?

    var body: some View {
        if let detail = model.detail(forBean: beanID) {
            content(detail, history: model.history(forBean: beanID))
                .navigationTitle(detail.bean.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !detail.bean.archived {
                        Button("Edit") { editing = true }
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

    private func content(_ detail: BeanDetail, history: AppModel.BeanHistory) -> some View {
        let bean = detail.bean
        let today = model.today

        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bean.name).font(.title2.weight(.semibold))
                    Text(detail.provenance.isEmpty ? bean.roaster : "\(bean.roaster) · \(detail.provenance)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let flavour = bean.flavourProfile {
                        Text(flavour).font(.footnote).foregroundStyle(.secondary)
                    }
                    if bean.isFrozen || bean.archived {
                        Label(bean.archived ? "Finished" : "Frozen", systemImage: bean.archived ? "checkmark.circle" : "snowflake")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(bean.archived ? Color.secondary : Color.cyan)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                ConsumptionMeter(detail: detail)
            }

            if let track = detail.ageTrack, let roast = bean.roastDate, let ready = bean.readyDate {
                Section("Age") {
                    AgeBar(track: track)
                    HStack {
                        Text("Roasted \(Format.shortDay(roast))")
                        Spacer()
                        Text("Rested \(Format.shortDay(ready))")
                        Spacer()
                        if let finishAge = detail.finishAge {
                            Text("Last cup, day \(finishAge)")
                                .foregroundStyle(finishAge > BeanDetail.oldFinishAge ? Color.red : Color.secondary)
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Roast date") {
                    if let roast = bean.roastDate {
                        Text(Format.mediumDay(roast))
                    } else {
                        Text("Not set").foregroundStyle(.orange)
                    }
                }
                if let age = detail.currentAge {
                    LabeledContent("Current age") {
                        if bean.frozenDaysToDate > 0, let calendar = detail.calendarAge {
                            Text("\(age) d (\(calendar) calendar, \(bean.frozenDaysToDate) frozen)")
                        } else {
                            Text("\(age) d")
                        }
                    }
                }
                LabeledContent("Rest required", value: "\(bean.effectiveRestDays) d")
                if let ready = bean.readyDate {
                    LabeledContent(ready <= today ? "Ready since" : "Ready date", value: Format.mediumDay(ready))
                } else {
                    LabeledContent("Ready date") { Text("Unknown").foregroundStyle(.orange) }
                }
                if !bean.isFrozen, let grams = bean.freezeAfterGrams {
                    LabeledContent("Freeze after", value: "\(Format.grams(grams)) g consumed")
                }
                if bean.isFrozen, let thaw = bean.plannedThawDate {
                    LabeledContent("Planned thaw", value: Format.mediumDay(thaw))
                }
            }
            .monospacedDigit()

            if !bean.archived {
                Section {
                    Button {
                        confirmingFreeze = bean
                    } label: {
                        Label(bean.isFrozen ? "Thaw bag" : "Freeze bag", systemImage: bean.isFrozen ? "sun.max" : "snowflake")
                    }
                    .tint(bean.isFrozen ? .orange : .cyan)
                }
            }

            if !history.recentBrews.isEmpty {
                Section("Recent brews") {
                    ForEach(Array(history.recentBrews.enumerated()), id: \.offset) { _, brew in
                        HStack {
                            Text(Format.shortDay(brew.creationDate)).foregroundStyle(.secondary)
                            Text("\(Format.grams(brew.groundCoffeeGrams)) g")
                            Spacer()
                            if let rating = brew.rating {
                                Text("★ \(Format.grams(rating))").foregroundStyle(.orange)
                            } else {
                                Text("—").foregroundStyle(.tertiary)
                            }
                        }
                        .font(.callout.monospacedDigit())
                    }
                }
            }

            if !history.freezeEvents.isEmpty {
                Section("Freezer") {
                    ForEach(Array(history.freezeEvents.enumerated()), id: \.offset) { _, event in
                        Label(
                            "\(event.kind == .freeze ? "Frozen" : "Thawed") \(Format.mediumDay(event.date))",
                            systemImage: event.kind == .freeze ? "snowflake" : "drop"
                        )
                        .font(.callout)
                    }
                }
            }
        }
    }
}

private struct ConsumptionMeter: View {
    let detail: BeanDetail

    var body: some View {
        let bean = detail.bean
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.grams(max(0, bean.remainingGrams).rounded()))
                    .font(.title.weight(.medium).monospacedDigit())
                Text("g of \(Format.grams(bean.weightGrams)) left")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let days = detail.daysLeft {
                    Text("≈ \(days) more \(days == 1 ? "day" : "days")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: detail.fractionConsumed)
                .tint(.orange)
            HStack {
                Text("\(Format.grams(bean.totalBrewedGrams.rounded())) g brewed")
                Spacer()
                if let start = detail.start, let finish = detail.finish {
                    Text("\(Format.shortDay(start)) → \(Format.shortDay(finish))")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Roast → ready (resting, muted) → today (accent) along the bag's life,
/// with a tick at today.
private struct AgeBar: View {
    let track: BeanDetail.AgeTrack

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let rest = width * track.restFraction
            let now = width * track.todayFraction
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.secondary.opacity(0.5)).frame(width: rest)
                Rectangle().fill(Color.orange)
                    .frame(width: max(0, now - rest))
                    .offset(x: rest)
                Rectangle().fill(Color.primary)
                    .frame(width: 2, height: 12)
                    .offset(x: min(max(0, now - 1), width - 2))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel("Age")
        .accessibilityValue("\(Int(track.todayFraction * 100)) percent of the way from roast to last cup")
    }
}
