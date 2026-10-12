import CoffeeCore
import SwiftUI

/// A bag's run through the month, for the medium widget's list.
struct MonthBag: Hashable {
    let id: String
    let name: String
    let roaster: String
    let start: String
    /// Exclusive.
    let end: String

    /// The bags in the month that aren't finished yet, in the order they're
    /// drunk; all of the month's bags once none are left.
    static func upcoming(_ events: [CalendarEvent], month: String, today: String) -> [MonthBag] {
        let monthEnd = DateUtils.addMonths(month, 1)
        var order: [String] = []
        var bags: [String: MonthBag] = [:]
        for event in events.sorted(by: { $0.start < $1.start }) {
            guard case .bean(let id, let roaster) = event.kind, event.start < monthEnd, event.end > month else { continue }
            if let bag = bags[id] {
                bags[id] = MonthBag(id: id, name: bag.name, roaster: roaster, start: bag.start, end: max(bag.end, event.end))
            } else {
                order.append(id)
                bags[id] = MonthBag(id: id, name: event.title, roaster: roaster, start: event.start, end: event.end)
            }
        }
        let all = order.compactMap { bags[$0] }
        let unfinished = all.filter { $0.end > today }
        return unfinished.isEmpty ? all : unfinished
    }
}

/// The medium widget's key: a dot in the roaster's colour, the bag's name,
/// and when it starts.
struct BagList: View {
    let bags: [MonthBag]
    let entry: MonthEntry

    private static let rows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.snapshot == nil {
                Text("Open the app to load the schedule")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.accent)
            } else if bags.isEmpty {
                Text("No bags this month").font(.system(size: 11)).foregroundStyle(Palette.text2)
            }
            ForEach(bags.prefix(Self.rows), id: \.self) { bag in
                row(bag).frame(maxHeight: .infinity)
            }
            // Keep rows the same height however many there are
            ForEach(0..<max(0, Self.rows - max(1, bags.count)), id: \.self) { _ in
                Color.clear.frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ bag: MonthBag) -> some View {
        let isCurrent = bag.start <= entry.today
        return HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: entry.snapshot?.roasterColors[bag.roaster] ?? RoasterColor.forRoaster(bag.roaster).border))
                .frame(width: 7, height: 7)
            Text(bag.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(isCurrent ? "now" : Self.day(bag.start))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Palette.accent : Palette.text2)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// "Oct 13" for an ISO day, read in UTC so the day can't shift.
    private static func day(_ iso: String) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = TimeZone(identifier: "UTC") ?? .current
        return DateUtils.noonUTC(iso).formatted(style)
    }
}
