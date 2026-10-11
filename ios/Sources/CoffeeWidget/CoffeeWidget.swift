import SwiftUI
import WidgetKit

/// The app's widgets. xtool packs this target as an app extension (see
/// `extensions` in xtool.yml).
@main
struct CoffeeWidgets: WidgetBundle {
    var body: some Widget {
        TestWidget()
    }
}

/// A placeholder that shows today's date, to prove a widget built with
/// xtool installs and runs.
struct TestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CoffeeTest", provider: TestProvider()) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text("Coffee Scheduler")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.88, green: 0.67, blue: 0.27))
                Text(entry.date, style: .date)
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.96, green: 0.93, blue: 0.87))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(Color(red: 0.08, green: 0.07, blue: 0.05), for: .widget)
        }
        .configurationDisplayName("Coffee test")
        .description("Checks that a widget built with xtool works.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TestEntry: TimelineEntry {
    let date: Date
}

struct TestProvider: TimelineProvider {
    func placeholder(in context: Context) -> TestEntry {
        TestEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TestEntry) -> Void) {
        completion(TestEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TestEntry>) -> Void) {
        completion(Timeline(entries: [TestEntry(date: .now)], policy: .after(.now.addingTimeInterval(3600))))
    }
}
