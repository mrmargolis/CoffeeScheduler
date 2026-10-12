import CoffeeCore
import SwiftUI
import WidgetKit

/// The app's widgets. xtool packs this target as an app extension (see
/// `extensions` in xtool.yml).
@main
struct CoffeeWidgets: WidgetBundle {
    var body: some Widget {
        MonthWidget()
    }
}

/// The current month's calendar, as on the app's Schedule screen. Tapping it
/// opens the app, as tapping any widget does.
struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CoffeeMonth", provider: MonthProvider()) { entry in
            MonthWidgetView(entry: entry)
                .containerBackground(Palette.ground, for: .widget)
        }
        .configurationDisplayName("Coffee month")
        .description("This month's bags, skipped days and days with no coffee.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct MonthEntry: TimelineEntry {
    let date: Date
    /// The ISO day the entry is drawn for.
    let today: String
    /// First of the month shown, which the arrows move.
    let month: String
    /// Nil until the app has written one.
    let snapshot: WidgetSnapshot?
}

struct MonthProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthEntry {
        MonthEntry(date: .now, today: DateUtils.today(), month: DateUtils.firstOfMonth(DateUtils.today()), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (MonthEntry) -> Void) {
        completion(Self.entry())
    }

    /// One entry, redrawn just after midnight so today's marker moves on.
    /// The app reloads the widget itself whenever the schedule changes.
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<MonthEntry>) -> Void) {
        let tomorrow = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400 + 60)
        completion(Timeline(entries: [Self.entry()], policy: .after(tomorrow)))
    }

    private static func entry() -> MonthEntry {
        let today = DateUtils.today()
        return MonthEntry(date: .now, today: today, month: ShownMonth.current(today: today), snapshot: load())
    }

    /// The snapshot the app last wrote into the shared App Group container.
    private static func load() -> WidgetSnapshot? {
        guard
            let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup),
            let data = try? Data(contentsOf: folder.appendingPathComponent(WidgetSnapshot.fileName))
        else { return nil }
        return try? WidgetSnapshot(decoding: data)
    }
}

/// The app's colours (`Theme` in the app target, which the widget can't import).
enum Palette {
    static let ground = Color(hex: "#15110D")
    /// The line over each week of the month grid.
    static let weekLine = Color(hex: "#5E4E3B")
    static let text = Color(hex: "#F4ECDD")
    static let text2 = Color(hex: "#BBAA92")
    static let text3 = Color(hex: "#94836C")
    static let dim = Color(hex: "#6E5F4C")
    static let accent = Color(hex: "#E0AA45")
    static let gap = Color(hex: "#E5766A")
    static let gapText = Color(hex: "#F0A096")
}

extension Color {
    /// A colour from "#rrggbb".
    init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
