import CoffeeCore
import Foundation

/// The parts of the model that change nothing in it: how it is made at
/// launch, a bag's detail, and reading an export.
extension AppModel {
    /// The app's model: the iCloud Drive database, or in a debug build
    /// launched with `-sample-data` (as the UI tests do), the sample data in
    /// memory with today pinned, so every run starts from the same state.
    static func forLaunch() -> AppModel {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-sample-data"), let store = try? SampleData.store() {
                return AppModel(store: store, today: SampleData.today, folderName: "Coffee")
            }
        #endif
        return AppModel()
    }

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

    /// Read and parse an export, off the main actor.
    @concurrent
    nonisolated static func readExport(at url: URL) async throws -> BeanConquerorParser.ParseResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        // Files shared into the app land in Documents/Inbox; don't let them pile up.
        if url.path.contains("/Documents/Inbox/") {
            try? FileManager.default.removeItem(at: url)
        }
        return BeanConquerorParser.parse(zipData: data)
    }
}
