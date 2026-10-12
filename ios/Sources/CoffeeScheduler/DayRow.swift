import CoffeeCore
import SwiftUI

/// One day in the week list: its date, then the bags drunk that day.
struct DayRow: View {
    static let dateWidth: CGFloat = 44

    @Environment(AppModel.self) private var model
    let day: ScheduleDay
    /// Each bag's run through the schedule, to mark its first and last cup.
    let runs: [String: BagRun]
    let openBean: (String) -> Void
    let openDay: () -> Void

    private var isToday: Bool { day.date == model.today }
    private var override: ConsumptionOverride? { model.consumptionOverride(on: day.date) }
    /// The override as it's shown: not on a skipped or already brewed day.
    private var shownOverride: ConsumptionOverride? { day.isSkip || day.isActual ? nil : override }

    var body: some View {
        HStack(spacing: 12) {
            dateButton
            VStack(alignment: .leading, spacing: 8) {
                status
                ForEach(day.consumptions, id: \.beanID) { cup($0) }
                // One bag's row carries the override itself
                if let shownOverride, day.consumptions.count != 1 {
                    OverridePill(grams: shownOverride.dailyGrams)
                }
            }
        }
        .frame(minHeight: 44)
        .opacity(day.isActual && !isToday ? 0.6 : 1)
        .listRowBackground(RowCard(tile: isToday ? .today : .none))
    }

    /// The date opens the day's options; the bags open their detail.
    private var dateButton: some View {
        Button(action: openDay) {
            VStack(spacing: 0) {
                Text(isToday ? "Today" : Format.weekday(day.date))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(isToday ? Theme.accent : Theme.text3)
                Text(Format.dayNumber(day.date))
                    .font(.title3.weight(isToday ? .bold : .semibold))
                    .monospacedDigit()
            }
            .frame(width: Self.dateWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Format.longDay(day.date))
        .accessibilityHint("Day options")
        .accessibilityIdentifier("day-\(day.date)")
        .accessibilityValue(accessibilityState)
    }

    @ViewBuilder
    private var status: some View {
        if day.isSkip {
            // An HStack, not a Label: a Label sets the row's separator
            // inset and draws its icon at title size
            HStack(spacing: 6) {
                Image(systemName: "airplane").font(.caption)
                Text(model.skipReason(on: day.date) ?? "Skipped")
            }
            .foregroundStyle(Theme.text2)
        } else if day.isGap && day.isActual {
            // A past day nothing was logged for: not an alarm
            Text("No brews logged").foregroundStyle(Theme.text3)
        } else if day.isGap {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle").font(.caption)
                Text("No coffee")
            }
            .foregroundStyle(Theme.gapText)
        }
    }

    /// One button per bag: a day can hold two, and a row-wide link couldn't
    /// tell them apart.
    private func cup(_ consumption: Consumption) -> some View {
        let note = self.note(consumption)
        return Button {
            openBean(consumption.beanID)
        } label: {
            HStack(spacing: 12) {
                RoasterRail(color: model.rail(consumption.roaster), width: 4, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(consumption.beanName).font(.callout.weight(.semibold)).lineLimit(1)
                    if !note.text.isEmpty {
                        Text(note.text)
                            .font(.caption)
                            .foregroundStyle(note.isEarly ? Theme.accent : Theme.text2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let shownOverride, day.consumptions.count == 1 {
                    OverridePill(grams: shownOverride.dailyGrams)
                } else {
                    Text("\(Format.grams(consumption.grams)) g").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        // Plain, not borderless: borderless tints the label
        .buttonStyle(.plain)
    }

    /// Under the bag's name: its roaster, then an early start or the age at
    /// the bag's first or last cup.
    private func note(_ consumption: Consumption) -> (text: String, isEarly: Bool) {
        var parts = consumption.roaster.isEmpty ? [] : [consumption.roaster]
        if let early = consumption.daysEarly, early > 0 {
            parts.append("\(Format.days(early)) early")
            return (parts.joined(separator: " · "), true)
        }
        if let run = runs[consumption.beanID], let ages = model.ageRanges[consumption.beanID] {
            if run.start == run.end {
                parts.append("day \(ages.start)")
            } else if day.date == run.start {
                parts.append("first cup, day \(ages.start)")
            } else if day.date == run.end {
                parts.append("last cup, day \(ages.finish)")
            }
        }
        return (parts.joined(separator: " · "), false)
    }
}

extension DayRow {
    /// What VoiceOver (and the UI tests) read for a day besides its date.
    var accessibilityState: String {
        var parts: [String] = []
        if day.isSkip { parts.append("Skipped") }
        if let override, !day.isSkip { parts.append("\(Format.grams(override.dailyGrams))g day") }
        if day.isGap && !day.isActual { parts.append("No coffee") }
        return parts.joined(separator: ", ")
    }
}

/// A day with its own amount: "60 g day" in gold.
private struct OverridePill: View {
    let grams: Double

    var body: some View {
        Text("\(Format.grams(grams)) g day")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Theme.accent.opacity(0.18), in: Capsule())
    }
}
