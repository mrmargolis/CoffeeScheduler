import CoffeeCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var schedule: [ScheduleDay] = []
    private(set) var activeBeans: [Bean] = []
    private(set) var archivedBeans: [Bean] = []
    /// Skip ranges from today on.
    private(set) var skipRanges: [SkipRange] = []
    /// Consumption overrides within the schedule window.
    private(set) var consumptionOverrides: [ConsumptionOverride] = []
    private(set) var settings = ScheduleSettings(dailyConsumptionGrams: Scheduler.defaultDailyGrams, defaultRestDays: 30)
    private(set) var today = DateUtils.today()

    /// Shown as an alert: import results and errors.
    var message: Message?

    struct Message: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    /// Nil for a sample-data model, which never touches iCloud Drive.
    @ObservationIgnored private let location: DatabaseLocation?
    @ObservationIgnored private var store: CoffeeStore?
    @ObservationIgnored private let fixedToday: String?
    @ObservationIgnored private let fixedFolderName: String?

    var hasFolder: Bool { folderName != nil }
    var folderName: String? { fixedFolderName ?? location?.folder?.lastPathComponent }

    init() {
        location = DatabaseLocation()
        fixedToday = nil
        fixedFolderName = nil
        reloadFromICloud()
    }

    /// A model over a given database with "today" pinned, for screenshots and
    /// previews. Changes stay in that database; nothing goes to iCloud Drive.
    init(store: CoffeeStore, today: String, folderName: String? = nil) {
        location = nil
        fixedToday = today
        fixedFolderName = folderName
        self.store = store
        perform("Couldn't load the database") { try refresh() }
    }

    // MARK: - Lifecycle

    /// Pick up changes made on another device or by the web app, then refresh.
    /// Called at launch and whenever the app comes back to the foreground.
    func reloadFromICloud() {
        guard let location else { return }
        perform("Couldn't read the database from iCloud Drive") {
            store = nil // SQLite must let go of the file before it is replaced
            try location.pullIfNewer()
            try openStore()
        }
    }

    func chooseFolder(_ url: URL) {
        guard let location else { return }
        perform("Couldn't use that folder") {
            store = nil
            try location.choose(folder: url)
            try openStore()
        }
    }

    private func openStore() throws {
        if store == nil, let location {
            store = try CoffeeStore(url: location.workingCopy)
        }
        try refresh()
    }

    private func refresh() throws {
        guard let store else { return }
        today = fixedToday ?? DateUtils.today()
        try store.autoThaw(today: today)
        try store.autoFreeze(today: today)

        settings = try store.settings()
        activeBeans = try store.beans(archived: false, today: today)
        archivedBeans = try store.beans(archived: true, today: today)
        skipRanges = try store.skipRanges(from: today)
        // Same window as the web app: two months back, four forward.
        let start = DateUtils.firstOfMonth(DateUtils.addMonths(today, -2))
        schedule = try store.schedule(start: start, end: DateUtils.addMonths(today, 4), today: today)
        consumptionOverrides = try store.consumptionOverrides(from: start)
    }

    /// Save the working copy to iCloud Drive after a change.
    private func save() throws {
        try refresh()
        try location?.push()
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
            if let location {
                store = nil
                try location.pullIfNewer()
                try openStore()
            }

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

    /// Save a bag's settings. Returns an error message to show in the form,
    /// or nil once saved: the app-wide alert can't appear over a sheet.
    func updateBeanSettings(id: String, _ settings: BeanSettings) -> String? {
        guard let store else { return "The database isn't open." }
        do {
            try store.updateBeanSettings(id: id, settings)
            try save()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Freeze a bag, or thaw a frozen one, as of today.
    func toggleFreeze(id: String) {
        perform("Couldn't update the bag") {
            try store?.toggleFreeze(id: id, today: today)
            try save()
        }
    }

    /// Save the queue in this order; the scheduler treats it as authoritative.
    func reorderQueue(_ ids: [String]) {
        perform("Couldn't reorder the queue") {
            try store?.reorderQueue(ids)
            try save()
        }
    }

    /// Return one bag, or with nil the whole queue, to automatic order.
    func clearQueueOrder(id: String? = nil) {
        perform("Couldn't reorder the queue") {
            if let id {
                try store?.clearQueuePosition(id: id)
            } else {
                try store?.clearQueueOrder()
            }
            try save()
        }
    }

    /// Skip a day (travel etc.), or stop skipping it.
    func toggleSkipDay(_ date: String) {
        perform("Couldn't update skip days") {
            try store?.toggleSkipDay(date)
            try save()
        }
    }

    func deleteSkipRange(id: Int) {
        perform("Couldn't update skip days") {
            try store?.deleteSkipRange(id: id)
            try save()
        }
    }

    func consumptionOverride(on date: String) -> ConsumptionOverride? {
        consumptionOverrides.first { $0.covers(date) }
    }

    /// Set a different amount for one day. Returns an error message to show
    /// in the day sheet, or nil once saved.
    func setConsumptionOverride(date: String, dailyGrams: Double, doseSizeGrams: Double) -> String? {
        guard let store else { return "The database isn't open." }
        do {
            try store.setConsumptionOverride(date: date, dailyGrams: dailyGrams, doseSizeGrams: doseSizeGrams)
            try save()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func deleteConsumptionOverride(id: Int) {
        perform("Couldn't clear the override") {
            try store?.deleteConsumptionOverride(id: id)
            try save()
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
