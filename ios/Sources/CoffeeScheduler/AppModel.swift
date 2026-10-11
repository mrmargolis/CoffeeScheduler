import CoffeeCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var schedule: [ScheduleDay] = []
    private(set) var activeBeans: [Bean] = []
    private(set) var archivedBeans: [Bean] = []
    private(set) var settings = ScheduleSettings(dailyConsumptionGrams: Scheduler.defaultDailyGrams, defaultRestDays: 30)
    private(set) var today = DateUtils.today()

    /// Shown as an alert: import results and errors.
    var message: Message?

    struct Message: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    @ObservationIgnored private let location = DatabaseLocation()
    @ObservationIgnored private var store: CoffeeStore?

    var hasFolder: Bool { location.folder != nil }
    var folderName: String? { location.folder?.lastPathComponent }

    init() {
        reloadFromICloud()
    }

    // MARK: - Lifecycle

    /// Pick up changes made on another device or by the web app, then refresh.
    /// Called at launch and whenever the app comes back to the foreground.
    func reloadFromICloud() {
        perform("Couldn't read the database from iCloud Drive") {
            store = nil // SQLite must let go of the file before it is replaced
            try location.pullIfNewer()
            try openStore()
        }
    }

    func chooseFolder(_ url: URL) {
        perform("Couldn't use that folder") {
            store = nil
            try location.choose(folder: url)
            try openStore()
        }
    }

    private func openStore() throws {
        if store == nil {
            store = try CoffeeStore(url: location.workingCopy)
        }
        try refresh()
    }

    private func refresh() throws {
        guard let store else { return }
        today = DateUtils.today()
        try store.autoThaw(today: today)
        try store.autoFreeze(today: today)

        settings = try store.settings()
        activeBeans = try store.beans(archived: false, today: today)
        archivedBeans = try store.beans(archived: true, today: today)
        // Same window as the web app: two months back, four forward.
        let start = DateUtils.firstOfMonth(DateUtils.addMonths(today, -2))
        schedule = try store.schedule(start: start, end: DateUtils.addMonths(today, 4), today: today)
    }

    /// Save the working copy to iCloud Drive after a change.
    private func save() throws {
        try refresh()
        try location.push()
    }

    // MARK: - Bean detail

    func detail(forBean id: String) -> BeanDetail? {
        guard let bean = activeBeans.first(where: { $0.id == id }) ?? archivedBeans.first(where: { $0.id == id })
        else { return nil }
        return BeanDetail(
            bean: bean,
            schedule: schedule,
            dailyConsumptionGrams: settings.dailyConsumptionGrams,
            today: today
        )
    }

    struct BeanHistory {
        var recentBrews: [BrewRecord] = []
        var freezeEvents: [FreezeEvent] = []
    }

    /// Read from the database on demand; small enough to query per view update.
    func history(forBean id: String) -> BeanHistory {
        guard let store else { return BeanHistory() }
        return BeanHistory(
            recentBrews: (try? store.recentBrews(beanID: id)) ?? [],
            freezeEvents: (try? store.freezeEvents(beanID: id)) ?? []
        )
    }

    // MARK: - Actions

    /// Import a BeanConqueror export, from the share sheet or the file picker.
    func importExport(at url: URL) {
        perform("Import failed") {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            // Files shared into the app land in Documents/Inbox; don't let them pile up.
            if url.path.contains("/Documents/Inbox/") {
                try? FileManager.default.removeItem(at: url)
            }

            let parsed = BeanConquerorParser.parse(zipData: data)
            if parsed.beans.isEmpty && !parsed.errors.isEmpty {
                throw LocationError(parsed.errors.joined(separator: "\n"))
            }

            // Fold in edits from other devices before writing over them.
            store = nil
            try location.pullIfNewer()
            try openStore()

            guard let store else { return }
            let summary = try store.importExport(parsed)
            try save()

            var body = "\(summary.beansImported) beans, \(summary.brewsImported) brews."
            if !summary.errors.isEmpty {
                body += "\n\n\(summary.errors.count) skipped:\n" + summary.errors.prefix(5).joined(separator: "\n")
            }
            message = Message(title: "Imported", body: body)
        }
    }

    func updateSettings(_ newValue: ScheduleSettings) {
        perform("Couldn't save settings") {
            try store?.updateSettings(newValue)
            try save()
        }
    }

    private func perform(_ failure: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            message = Message(title: failure, body: error.localizedDescription)
        }
    }
}
