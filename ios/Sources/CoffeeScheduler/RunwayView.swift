import CoffeeCore
import SwiftUI

/// The strip at the top of the schedule: how long the coffee lasts, what's on
/// the grinder, and the one thing most worth a look. Mirrors
/// `src/components/RunwayStrip.tsx`; tapping a bag opens it.
struct RunwayView: View {
    let summary: RunwaySummary
    let openBean: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(summary.daysOfCoffee)")
                    .font(.system(.largeTitle, design: .rounded).weight(.medium).monospacedDigit())
                Text(summary.daysOfCoffee == 1 ? "day of coffee" : "days of coffee")
                    .foregroundStyle(.secondary)
            }

            if let bean = summary.brewing {
                Button { openBean(bean.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "cup.and.saucer.fill").foregroundStyle(.brown)
                        Text(bean.name).fontWeight(.medium).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Format.grams(max(0, bean.remainingGrams).rounded())) g left")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("On the grinder: \(bean.name)")
            }

            switch summary.attention {
            case .gap(let date):
                Label {
                    HStack {
                        Text("No coffee scheduled from")
                        Spacer(minLength: 4)
                        Text(Format.shortDay(date)).font(.caption.monospacedDigit())
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
            case .earlyStart(let bean, let days, let start):
                Button { openBean(bean.id) } label: {
                    Label {
                        HStack {
                            Text("\(bean.name) starts \(days) \(days == 1 ? "day" : "days") before it's rested")
                                .lineLimit(2)
                            Spacer(minLength: 4)
                            if let start {
                                Text(Format.shortDay(start)).font(.caption.monospacedDigit())
                            }
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.orange)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            case nil:
                EmptyView()
            }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}
