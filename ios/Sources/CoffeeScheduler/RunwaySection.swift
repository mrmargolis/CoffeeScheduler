import CoffeeCore
import SwiftUI

/// When the coffee runs out and when to buy the next bag. It goes under the
/// calendar, never above it, and isn't there while nothing runs out.
struct RunwaySection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let runway = model.runway {
            let isLate = runway.daysShort > 0
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "cart")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isLate ? Theme.gapText : Theme.accent)
                        .frame(width: 36, height: 36)
                        .background((isLate ? Theme.gap : Theme.accent).opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.title(runway)).font(.callout.weight(.semibold))
                        Text(Self.advice(runway, today: model.today)).font(.caption).foregroundStyle(Theme.text2)
                    }
                }
                .frame(minHeight: 48)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("runway")
            }
            .listRowBackground(Theme.card)
        }
    }

    /// "Coffee through Nov 23".
    static func title(_ runway: Runway) -> String {
        runway.lastCoffeeDay.map { "Coffee through \(Format.shortDay($0))" } ?? "No coffee ready"
    }

    /// When to buy, or once that day has gone, how long the wait will be.
    static func advice(_ runway: Runway, today: String) -> String {
        if runway.daysShort > 0 {
            let rested = Format.shortDay(runway.restedIfBoughtToday)
            return "A bag bought today is rested \(rested), \(Format.days(runway.daysShort)) after you run out."
        }
        let day = runway.buyBy == today ? "today" : "by \(Format.shortDay(runway.buyBy))"
        return "Buy the next bag \(day) so it's rested in time."
    }
}
