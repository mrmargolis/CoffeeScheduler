import CoffeeCore
import SwiftUI
import WidgetKit
import os

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
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup) else {
            log.error("No App Group container: the widget was signed without the group")
            return nil
        }
        do {
            return try WidgetSnapshot(decoding: Data(contentsOf: folder.appendingPathComponent(WidgetSnapshot.fileName)))
        } catch {
            // Also what a new install says, until the app has been opened
            log.error("Couldn't read the snapshot: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Under the app's subsystem, so one filter shows both (see "Logs" in the README).
    private static let log = Logger(subsystem: "net.mattmargolis.CoffeeScheduler", category: "widget-extension")
}
