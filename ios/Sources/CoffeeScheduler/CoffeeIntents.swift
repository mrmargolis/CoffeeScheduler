import AppIntents
import CoffeeCore
import Foundation

/// The day a Siri question is about.
enum CoffeeDay: String, AppEnum {
    case today
    case tomorrow

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Day"
    static let caseDisplayRepresentations: [CoffeeDay: DisplayRepresentation] = [
        .today: "today",
        .tomorrow: "tomorrow",
    ]

    var spoken: SpokenSchedule.Day { self == .today ? .today : .tomorrow }
}

/// "What's my coffee today?": says which bags are scheduled, without
/// opening the app. iOS finds this through the Metadata.appintents bundle
/// in Support/IntentsMetadata, which has to be refreshed when it changes.
struct CoffeeForDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Coffee for the day"
    static let description = IntentDescription("Says which coffee is scheduled today or tomorrow.")

    @Parameter(title: "Day", default: .today)
    var day: CoffeeDay

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try Self.answer(for: day.spoken))")
    }

    /// Reads the app's own copy of the database; it doesn't fetch from
    /// iCloud Drive, so it knows what the app knew when it was last open.
    @MainActor
    static func answer(for day: SpokenSchedule.Day) throws -> String {
        let store = try CoffeeStore(url: DatabaseLocation.workingCopyURL)
        let today = DateUtils.today()
        guard try !store.beans(archived: false, today: today).isEmpty else {
            return "There are no beans yet. Open Coffee Scheduler and import a BeanConqueror export first."
        }
        let date = DateUtils.addDays(today, day.offset)
        let schedule = try store.schedule(start: today, end: date, today: today)
        return SpokenSchedule.sentence(for: schedule.first { $0.date == date }, on: day)
    }
}

/// The phrases Siri answers without any setup.
struct CoffeeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CoffeeForDayIntent(),
            phrases: [
                "What's my coffee \(\.$day) in \(.applicationName)",
                "What coffee is \(\.$day) in \(.applicationName)",
                "What's my \(.applicationName) \(\.$day)",
                "Ask \(.applicationName) about my coffee \(\.$day)",
            ],
            shortTitle: "Coffee for the day",
            systemImageName: "cup.and.saucer"
        )
    }
}
