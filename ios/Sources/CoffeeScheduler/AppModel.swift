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
    private(set) var roasterDefaults: [RoasterDefault] = []
    /// Roasters in the beans, for adding a roaster default.
    private(set) var roasters: [String] = []
    /// Collision-free colours for the roasters in the schedule.
    private(set) var roasterColors: [String: RoasterColor] = [:]
    /// Each scheduled bag's age at its first and last cup.
    private(set) var ageRanges: [String: AgeRange] = [:]
    /// Consumption overrides within the schedule window.
    private(set) var consumptionOverrides: [ConsumptionOverride] = []
    private(set) var settings = ScheduleSettings(dailyConsumptionGrams: Scheduler.defaultDailyGrams, defaultRestDays: 30)
    /// When the coffee runs out; nil with no bags, or none running out in the schedule.
    private(set) var runway: Runway?
    private(set) var lastImportDate: String?
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
    /// The iCloud Drive work asked for so far: see `enqueue`.
    @ObservationIgnored private var syncWork: Task<Void, Never>?

    var hasFolder: Bool { folderName != nil }
    var folderName: String? { fixedFolderName ?? location?.folder?.lastPathComponent }

    init() {
        location = DatabaseLocation()
        fixedToday = nil
        fixedFolderName = nil
        // What was here last time shows at once; iCloud Drive's copy follows
        perform("Couldn't load the database") { try openStore() }
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

    /// Do a piece of iCloud Drive work after the ones already asked for, so
    /// that a pull and a push never overlap. The file copies wait off the
    /// main actor, so the app stays usable while iCloud Drive is slow.
    private func enqueue(_ failure: String, _ body: @escaping @MainActor () async throws -> Void) {
        let previous = syncWork
        syncWork = Task {
            await previous?.value
            do {
                try await body()
            } catch {
                self.message = Message(title: failure, body: error.localizedDescription)
            }
        }
    }

    /// Pick up changes made on another device, then refresh.
    /// Called at launch and whenever the app comes back to the foreground.
    func reloadFromICloud() {
        guard let location else { return }
        enqueue("Couldn't read the database from iCloud Drive") { try await self.pull(from: location) }
    }

    /// Take a newer database from iCloud Drive if there is one, then refresh
    /// either way: the day may have moved on.
    private func pull(from location: DatabaseLocation) async throws {
        var failure: (any Error)?
        do {
            try await location.pullIfNewer { store = nil }
        } catch {
            failure = error
        }
        try openStore()
        if let failure { throw failure }
    }

    func chooseFolder(_ url: URL) {
        guard let location else { return }
        enqueue("Couldn't use that folder") {
            try location.adopt(folder: url)
            if location.hasRemoteFile {
                try await self.pull(from: location)
            } else {
                try self.openStore()
                try await location.push()
            }
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
        roasterDefaults = try store.roasterDefaults()
        roasters = try store.roasters()
        activeBeans = try store.beans(archived: false, today: today)
        archivedBeans = try store.beans(archived: true, today: today)
        skipRanges = try store.skipRanges(from: today)
        // Two months back, four forward.
        let start = DateUtils.firstOfMonth(DateUtils.addMonths(today, -2))
        schedule = try store.schedule(start: start, end: DateUtils.addMonths(today, 4), today: today)
        consumptionOverrides = try store.consumptionOverrides(from: start)
        roasterColors = Scheduler.roasterColors(schedule)
        ageRanges = Scheduler.ageRanges(schedule, beans: activeBeans + archivedBeans, today: today)
        runway = activeBeans.isEmpty ? nil : Scheduler.runway(schedule, restDays: settings.defaultRestDays, today: today)
        lastImportDate = try store.lastImportDate()
        // Sample data stays out of the real widget
        if location != nil {
            WidgetBridge.publish(WidgetSnapshot(schedule: schedule, skipRanges: skipRanges, roasterColors: roasterColors))
        }
        scheduleReminders()
    }

    /// Hand the schedule's reminders to iOS. Sample data sets none.
    func scheduleReminders() {
        guard location != nil else { return }
        let plan = ScheduleReminders.plan(schedule: schedule, beans: activeBeans, runway: runway, today: today)
        ReminderScheduler.schedule(plan, today: today)
    }

    /// After a change: refresh, and queue the working copy to be copied to
    /// iCloud Drive.
    private func save() throws {
        try refresh()
        guard let location else { return }
        location.workingCopyChanged()
        enqueue("Couldn't save to iCloud Drive") { try await location.push() }
    }

    // MARK: - Bean detail

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
        enqueue("Import failed") {
            let parsed = try await Self.readExport(at: url)
            if parsed.beans.isEmpty && !parsed.errors.isEmpty {
                throw LocationError(parsed.errors.joined(separator: "\n"))
            }

            // Fold in edits from other devices before writing over them.
            if let location = self.location {
                try await self.pull(from: location)
                try await location.backUp()
            }

            guard let store = self.store else { return }
            let summary = try store.importExport(parsed, on: self.today)
            try self.save()

            var body = "\(summary.beansImported) beans, \(summary.brewsImported) brews."
            if !summary.errors.isEmpty {
                body += "\n\n\(summary.errors.count) skipped:\n" + summary.errors.prefix(5).joined(separator: "\n")
            }
            self.message = Message(title: "Imported", body: body)
        }
    }

    /// Save a bag's settings. Returns an error message to show in the form,
    /// or nil once saved: the app-wide alert can't appear over a sheet.
    func updateBeanSettings(id: String, _ settings: BeanSettings) -> String? {
        saveFromForm { try $0.updateBeanSettings(id: id, settings) }
    }

    /// Make a change from a form and save it. Returns an error message for
    /// the form to show, or nil once saved.
    private func saveFromForm(_ change: (CoffeeStore) throws -> Void) -> String? {
        guard let store else { return "The database isn't open." }
        do {
            try change(store)
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

    /// Skip a stretch of days, or with `id` change that stretch. Returns an
    /// error message to show in the form, or nil once saved.
    func saveSkipRange(replacing id: Int?, start: String, end: String, reason: String) -> String? {
        saveFromForm { try $0.saveSkipRange(replacing: id, start: start, end: end, reason: reason) }
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
        saveFromForm { try $0.setConsumptionOverride(date: date, dailyGrams: dailyGrams, doseSizeGrams: doseSizeGrams) }
    }

    func deleteConsumptionOverride(id: Int) {
        perform("Couldn't clear the override") {
            try store?.deleteConsumptionOverride(id: id)
            try save()
        }
    }

    /// Set a roaster's default rest days, or remove it with nil.
    func setRoasterRestDays(_ roaster: String, _ restDays: Int?) {
        perform("Couldn't save the roaster default") {
            try store?.setRoasterRestDays(roaster, restDays)
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
