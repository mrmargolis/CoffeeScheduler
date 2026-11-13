import Foundation
import Testing

@testable import CoffeeCore

/// The bag's page from BeanConqueror: read from the export, kept in the
/// database and turned into a link.
@Suite struct BeanPageTests {
    private func page(_ typed: String?) -> String? {
        var bean = makeDetailBean()
        bean.url = typed
        return bean.pageURL?.absoluteString
    }

    @Test func readsTheBagsPageFromTheExport() throws {
        let export = try makeExport(beans: [bcBean(["url": "https://onyxcoffeelab.com/products/la-fortuna"]), bcBean(["url": ""])])
        let beans = BeanConquerorParser.parse(zipData: export, timeZone: utc).beans
        #expect(beans.map(\.url) == ["https://onyxcoffeelab.com/products/la-fortuna", nil])
    }

    @Test func keepsThePageAndFollowsItsChanges() throws {
        let store = try CoffeeStore.inMemory()
        let first = try makeExport(beans: [bcBean(["url": "septembercoffee.co/pepe"])])
        _ = try store.importExport(BeanConquerorParser.parse(zipData: first, timeZone: utc), on: "2026-02-01")
        #expect(try store.bean(id: "uuid-1", today: "2026-02-01")?.url == "septembercoffee.co/pepe")

        // Cleared in BeanConqueror, cleared here
        let second = try makeExport(beans: [bcBean()])
        _ = try store.importExport(BeanConquerorParser.parse(zipData: second, timeZone: utc), on: "2026-02-02")
        #expect(try store.bean(id: "uuid-1", today: "2026-02-02")?.url == nil)
    }

    @Test func addsThePageColumnToADatabaseWithoutIt() throws {
        // A version 1 file from before the bag's page was kept
        let db = try SQLiteDatabase(path: ":memory:")
        try db.execute(
            """
            CREATE TABLE beans (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, roaster TEXT NOT NULL DEFAULT '', roast_date TEXT,
              weight_grams REAL NOT NULL DEFAULT 0, cost REAL, flavour_profile TEXT, country TEXT, region TEXT,
              variety TEXT, processing TEXT, archived INTEGER NOT NULL DEFAULT 0, rest_days INTEGER,
              is_frozen INTEGER NOT NULL DEFAULT 0, notes TEXT, display_order INTEGER,
              planned_thaw_date TEXT, freeze_after_grams REAL
            );
            INSERT INTO beans (id, name, weight_grams) VALUES ('old', 'Old Bean', 250);
            PRAGMA user_version = 1;
            """)

        let store = try CoffeeStore(db: db)
        #expect(try store.bean(id: "old")?.url == nil)
        #expect(try db.query("PRAGMA user_version").first?.int("user_version") == 1)
    }

    @Test func linksToAPageTypedWithOrWithoutHttps() {
        #expect(page("https://onyxcoffeelab.com/products/x") == "https://onyxcoffeelab.com/products/x")
        #expect(page("http://example.com") == "http://example.com")
        #expect(page("  septembercoffee.co/pepe-jijon \n") == "https://septembercoffee.co/pepe-jijon")
    }

    @Test func hasNoLinkForNothingOrSomethingThatIsntAWebPage() {
        #expect(page(nil) == nil)
        #expect(page("  ") == nil)
        #expect(page("great coffee") == nil)
        #expect(page("localhost") == nil)
        #expect(page("ftp://example.com/file") == nil)
        #expect(page("javascript:alert(1)") == nil)
    }
}
