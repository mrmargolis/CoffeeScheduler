import Foundation
import Testing
@testable import CoffeeCore

@Suite struct CoffeeStoreTests {
    func importSample(into store: CoffeeStore) throws -> CoffeeStore.ImportSummary {
        let data = try makeExport(
            beans: [
                bcBean(),
                bcBean(["name": "Old Bean", "finished": true, "config": ["uuid": "uuid-2"]]),
            ],
            brews: [
                bcBrew(),
                bcBrew(["config": ["uuid": "brew-2", "unix_timestamp": 1706875200]]),
            ]
        )
        return try store.importExport(BeanConquerorParser.parse(zipData: data, timeZone: utc))
    }

    @Test func defaultSettings() throws {
        let settings = try CoffeeStore.inMemory().settings()
        #expect(settings == ScheduleSettings(dailyConsumptionGrams: 45, defaultRestDays: 30))
    }

    @Test func updateSettings() throws {
        let store = try CoffeeStore.inMemory()
        try store.updateSettings(ScheduleSettings(dailyConsumptionGrams: 37.5, defaultRestDays: 21))
        #expect(try store.settings() == ScheduleSettings(dailyConsumptionGrams: 37.5, defaultRestDays: 21))
    }

    @Test func importsBeansAndBrews() throws {
        let store = try CoffeeStore.inMemory()
        let summary = try importSample(into: store)
        #expect(summary.beansImported == 2)
        #expect(summary.brewsImported == 2)

        let active = try store.beans(archived: false, today: "2026-02-01")
        #expect(active.map(\.id) == ["uuid-1"])
        #expect(active.first?.totalBrewedGrams == 30)
        #expect(active.first?.remainingGrams == 220)
        #expect(active.first?.effectiveRestDays == 30)
        #expect(active.first?.readyDate == "2026-02-14")
        #expect(try store.beans(archived: true, today: "2026-02-01").map(\.id) == ["uuid-2"])
    }

    @Test func reimportReplacesBrewsAndKeepsUserFields() throws {
        let store = try CoffeeStore.inMemory()
        _ = try importSample(into: store)
        try store.db.run("UPDATE beans SET rest_days = 10, notes = 'mine' WHERE id = 'uuid-1'")
        _ = try importSample(into: store)

        let bean = try #require(try store.beans(archived: false).first)
        #expect(bean.totalBrewedGrams == 30)
        #expect(bean.restDays == 10)
        #expect(bean.notes == "mine")
    }

    @Test func roasterDefaultBeatsGlobalRestDays() throws {
        let store = try CoffeeStore.inMemory()
        _ = try importSample(into: store)
        try store.db.run("INSERT INTO roaster_defaults (roaster, rest_days) VALUES ('Test Roaster', 14)")
        #expect(try store.beans(archived: false).first?.effectiveRestDays == 14)
    }

    @Test func frozenDaysCountClosedAndOpenFreezes() throws {
        let store = try CoffeeStore.inMemory()
        _ = try importSample(into: store)
        try store.db.execute("""
            INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('uuid-1', 'freeze', '2026-01-20');
            INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('uuid-1', 'thaw', '2026-01-25');
            INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('uuid-1', 'freeze', '2026-02-01');
            """)
        #expect(try store.frozenDays(today: "2026-02-04")["uuid-1"] == 8)
    }

    @Test func autoThawAndFreeze() throws {
        let store = try CoffeeStore.inMemory()
        _ = try importSample(into: store)
        try store.db.run("UPDATE beans SET is_frozen = 1, planned_thaw_date = '2026-02-01' WHERE id = 'uuid-1'")
        try store.autoThaw(today: "2026-02-01")
        var bean = try #require(try store.beans(archived: false).first)
        #expect(bean.isFrozen == false)
        #expect(bean.plannedThawDate == nil)

        // 30g brewed; freezing after 40g triggers once within a minimum dose
        try store.db.run("UPDATE beans SET freeze_after_grams = 40, display_order = 1 WHERE id = 'uuid-1'")
        try store.autoFreeze(today: "2026-02-02")
        bean = try #require(try store.beans(archived: false).first)
        #expect(bean.isFrozen)
        #expect(bean.freezeAfterGrams == nil)
        #expect(bean.displayOrder == nil)
    }

    @Test func scheduleFromDatabase() throws {
        let store = try CoffeeStore.inMemory()
        _ = try importSample(into: store)
        try store.db.run("INSERT INTO skip_days (start_date, end_date) VALUES ('2026-02-15', '2026-02-15')")

        let days = try store.schedule(start: "2026-02-14", end: "2026-02-16", today: "2026-02-10")
        #expect(days.map(\.date) == ["2026-02-14", "2026-02-15", "2026-02-16"])
        #expect(days[0].consumptions.first?.beanID == "uuid-1")
        #expect(days[0].consumptions.first?.grams == 45)
        #expect(days[1].isSkip)
        #expect(days[2].consumptions.first?.grams == 45)
    }

    @Test func persistsToFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coffee-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let store = try CoffeeStore(url: url)
            _ = try importSample(into: store)
        }
        let reopened = try CoffeeStore(url: url)
        #expect(try reopened.beans(archived: false).count == 1)
        #expect(!FileManager.default.fileExists(atPath: url.path + "-wal"))
    }
}
