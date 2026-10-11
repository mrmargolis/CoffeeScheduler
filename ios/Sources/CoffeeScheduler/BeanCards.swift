import CoffeeCore
import SwiftUI

/// A bag in the queue: its place, what it is, whether it's ready, how much
/// is left and how old it will be when it's drunk.
struct QueueCard: View {
    @Environment(AppModel.self) private var model
    let bean: Bean
    /// The bag's first day in the schedule, if it's scheduled.
    let start: String?

    private var isOnGrinder: Bool { start.map { $0 <= model.today } ?? false }
    private var isOpened: Bool { bean.remainingGrams < bean.weightGrams }

    var body: some View {
        let color = model.rail(bean.roaster)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                QueueTile(order: bean.displayOrder, color: color, isSolid: isOnGrinder)
                BagTitle(name: bean.name, subtitle: Self.subtitle(bean))
                Spacer(minLength: 8)
                badge
            }
            MeterBar(fraction: bean.weightGrams > 0 ? max(0, bean.remainingGrams) / bean.weightGrams : 0, color: color)
            HStack(spacing: 4) {
                Text("\(Format.grams(max(0, bean.remainingGrams).rounded())) g").fontWeight(.bold)
                Text(amountNote).foregroundStyle(Theme.text2)
                Spacer(minLength: 8)
                age
            }
            .font(.footnote)
            .monospacedDigit()
            .lineLimit(1)
        }
        .cardBackground(Theme.card)
    }

    /// Roaster, then country and processing: "Square Mile · Ethiopia, natural".
    static func subtitle(_ bean: Bean) -> String {
        let origin = [bean.country, bean.processing].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return [bean.roaster, origin].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var badge: some View {
        if isOnGrinder {
            Badge(text: "On the grinder", color: Theme.accent, background: Theme.accent.opacity(0.18))
        } else if let ready = bean.readyDate {
            if ready <= model.today {
                Badge(text: "Ready", color: Theme.ready, background: Theme.ready.opacity(0.16))
            } else {
                Badge(text: "Ready \(Format.shortDay(ready))", color: Theme.text2, background: Theme.raised)
            }
        } else {
            Badge(text: "No roast date", color: Theme.accent, background: Theme.accent.opacity(0.18))
        }
    }

    /// After the grams left: "of 250 left", or for a full bag what's planned.
    private var amountNote: String {
        if isOpened { return "of \(Format.grams(bean.weightGrams)) left" }
        if let grams = bean.freezeAfterGrams { return "unopened · freeze after \(Format.grams(grams)) g" }
        if let start { return "unopened · starts \(Format.shortDay(start))" }
        return "unopened"
    }

    /// Age at first and last cup says more than the roast date; a bag that
    /// isn't scheduled has only the roast date.
    @ViewBuilder
    private var age: some View {
        if let ages = model.ageRanges[bean.id] {
            Text("Age \(Format.ages(ages))")
                .foregroundStyle(ages.finish > BeanDetail.oldFinishAge ? Theme.gapText : Theme.text2)
        } else if let roast = bean.roastDate {
            Text("Roasted \(Format.shortDay(roast))").foregroundStyle(Theme.text2)
        }
    }
}

/// A bag in the freezer, in a cooler card, with the day it comes out.
struct FrozenCard: View {
    static let ground = Color(hex: "#1A2226")

    @Environment(AppModel.self) private var model
    let bean: Bean

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "snowflake")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.frozenText)
                .frame(width: 36, height: 36)
                .background(Theme.frozen.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            BagTitle(name: bean.name, subtitle: subtitle)
            Spacer(minLength: 8)
            // A frozen bag's thaw date matters more than its ready date
            if let thaw = bean.plannedThawDate {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Thaws").font(.caption).foregroundStyle(Theme.text2)
                    Text(Format.shortDay(thaw)).font(.subheadline.bold()).foregroundStyle(Theme.frozenText)
                }
                .monospacedDigit()
            } else {
                Text("No thaw date").font(.caption).foregroundStyle(Theme.text2)
            }
        }
        .cardBackground(Self.ground)
    }

    /// "Onyx · 100 g · frozen at day 4".
    private var subtitle: String {
        var parts = bean.roaster.isEmpty ? [] : [bean.roaster]
        parts.append("\(Format.grams(max(0, bean.remainingGrams).rounded())) g")
        if let age = effectiveAge(roastDate: bean.roastDate, asOf: model.today, frozenDays: bean.frozenDaysToDate) {
            parts.append("frozen at day \(age)")
        }
        return parts.joined(separator: " · ")
    }
}

/// The square at the head of a queue card: the bag's number when the queue
/// has been ordered by hand, in its roaster's colour.
private struct QueueTile: View {
    let order: Int?
    let color: Color
    /// Filled for the bag being drunk, tinted and outlined for the rest.
    let isSolid: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        ZStack {
            shape.fill(color.opacity(isSolid ? 1 : 0.2))
            if !isSolid { shape.strokeBorder(color, lineWidth: 1) }
            if let order {
                Text("\(order)")
                    .font(.callout.bold())
                    .foregroundStyle(isSolid ? Theme.ground : Theme.text)
                    .monospacedDigit()
                    .accessibilityLabel("Position \(order)")
            } else {
                Circle().fill(isSolid ? Theme.ground : color).frame(width: 8, height: 8)
            }
        }
        .frame(width: 36, height: 36)
    }
}

/// A bag's name over one line about it.
struct BagTitle: View {
    let name: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.headline.bold()).lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle).font(.footnote).foregroundStyle(Theme.text2).lineLimit(1)
            }
        }
    }
}

/// A small rounded label: "Ready", "On the grinder".
struct Badge: View {
    let text: String
    let color: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(background, in: Capsule())
            .fixedSize()
    }
}

/// A thin bar filled to a 0...1 share.
struct MeterBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

extension View {
    /// A card drawn by the row itself, for lists whose rows are separate cards.
    func cardBackground(_ color: Color) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .contentShape(Rectangle())
    }
}
