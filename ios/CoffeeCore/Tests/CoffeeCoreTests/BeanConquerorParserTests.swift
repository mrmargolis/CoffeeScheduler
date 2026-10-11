import Foundation
import Testing
import ZIPFoundation

@testable import CoffeeCore

// Ported from src/__tests__/lib/bc-json-parser.test.ts.

let utc = TimeZone(identifier: "UTC")!

func makeZip(_ files: [String: Any]) throws -> Data {
    let archive = try Archive(accessMode: .create)
    for (path, contents) in files {
        let data = try JSONSerialization.data(withJSONObject: contents)
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }
    return try #require(archive.data)
}

func makeExport(beans: [[String: Any]] = [], brews: [[String: Any]] = [], extra: [String: Any] = [:]) throws -> Data {
    var files = extra
    files["Beanconqueror.json"] = ["BEANS": beans, "BREWS": brews]
    return try makeZip(files)
}

func bcBean(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var bean: [String: Any] = [
        "name": "Test Bean",
        "roaster": "Test Roaster",
        "roastingDate": "2026-01-15T00:00:00.000Z",
        "weight": 250,
        "cost": 16.5,
        "aromatics": "Floral, Citrus",
        "finished": false,
        "bean_information": [
            [
                "country": "Ethiopia",
                "region": "Yirgacheffe",
                "variety": "Heirloom",
                "processing": "Washed",
            ]
        ],
        "config": ["uuid": "uuid-1", "unix_timestamp": 1_700_000_000],
    ]
    bean.merge(overrides) { _, new in new }
    return bean
}

func bcBrew(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var brew: [String: Any] = [
        "bean": "uuid-1",
        "grind_weight": 15,
        "rating": 4,
        "config": ["uuid": "brew-1", "unix_timestamp": 1_706_788_800],  // 2024-02-01 12:00 UTC
    ]
    brew.merge(overrides) { _, new in new }
    return brew
}

@Suite struct BeanConquerorParserTests {
    @Test func parsesBeanFields() throws {
        let result = BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()]), timeZone: utc)
        #expect(result.errors.isEmpty)
        #expect(
            result.beans == [
                BeanConquerorParser.RawBean(
                    id: "uuid-1", name: "Test Bean", roaster: "Test Roaster", roastDate: "2026-01-15",
                    weightGrams: 250, cost: 16.5, flavourProfile: "Floral, Citrus", country: "Ethiopia",
                    region: "Yirgacheffe", variety: "Heirloom", processing: "Washed",
                    archived: false, isFrozen: false
                )
            ])
    }

    @Test func emptyAndZeroFieldsBecomeNil() throws {
        let bean = bcBean(["cost": 0, "aromatics": "", "roastingDate": "", "bean_information": [Any]()])
        let parsed = try #require(BeanConquerorParser.parse(zipData: try makeExport(beans: [bean])).beans.first)
        #expect(parsed.cost == nil)
        #expect(parsed.flavourProfile == nil)
        #expect(parsed.roastDate == nil)
        #expect(parsed.country == nil)
    }

    @Test func skipsBeanWithoutUUID() throws {
        let result = BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean(["config": [String: Any]()])]))
        #expect(result.beans.isEmpty)
        #expect(result.errors == ["Bean index 0: missing config.uuid, skipping"])
    }

    @Test func finishedBeansAreArchived() throws {
        let result = BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean(["finished": true])]))
        #expect(result.beans.first?.archived == true)
    }

    @Test func frozenBeanRecordsFreezeEvent() throws {
        let bean = bcBean(["frozenId": "F1", "frozenDate": "2026-02-01T10:00:00.000Z"])
        let result = BeanConquerorParser.parse(zipData: try makeExport(beans: [bean]))
        #expect(result.beans.first?.isFrozen == true)
        #expect(result.freezeEvents == [.init(beanID: "uuid-1", frozenDate: "2026-02-01")])
    }

    @Test func unfrozenBeanIsNotFrozen() throws {
        let bean = bcBean(["frozenId": "F1", "unfrozenDate": "2026-03-01T10:00:00.000Z"])
        let result = BeanConquerorParser.parse(zipData: try makeExport(beans: [bean]))
        #expect(result.beans.first?.isFrozen == false)
        #expect(result.freezeEvents.isEmpty)
    }

    @Test func parsesBrews() throws {
        let bean = bcBean(["roastingDate": "2024-01-15T00:00:00.000Z"])
        let result = BeanConquerorParser.parse(zipData: try makeExport(beans: [bean], brews: [bcBrew()]), timeZone: utc)
        #expect(
            result.brews == [
                .init(
                    beanID: "uuid-1", groundCoffeeGrams: 15, creationDate: "2024-02-01", beanAgeDays: 17, rating: 4
                )
            ])
    }

    @Test func mergesAndDedupesSplitBrewFiles() throws {
        let data = try makeExport(
            beans: [bcBean()],
            brews: [bcBrew()],
            extra: [
                "Beanconqueror_Brews_1.json": [
                    bcBrew(),  // duplicate of the main file's brew
                    bcBrew(["config": ["uuid": "brew-2", "unix_timestamp": 1_706_875_200]]),
                ]
            ]
        )
        let result = BeanConquerorParser.parse(zipData: data, timeZone: utc)
        #expect(result.brews.map(\.creationDate) == ["2024-02-01", "2024-02-02"])
    }

    @Test func skipsBrewsWithoutBeanOrDate() throws {
        let result = BeanConquerorParser.parse(
            zipData: try makeExport(brews: [
                bcBrew(["bean": "", "config": ["uuid": "a", "unix_timestamp": 1_706_788_800]]),
                bcBrew(["config": ["uuid": "b"]]),
            ]))
        #expect(result.brews.isEmpty)
        #expect(
            result.errors == [
                "Brew index 0: missing bean reference, skipping",
                "Brew index 1: invalid creation date, skipping",
            ])
    }

    @Test func missingMainFile() throws {
        let result = BeanConquerorParser.parse(zipData: try makeZip(["other.json": ["a": 1]]))
        #expect(result.errors == ["No Beanconqueror.json found in ZIP"])
    }

    @Test func notAZip() {
        let result = BeanConquerorParser.parse(zipData: Data("hello".utf8))
        #expect(result.errors.count == 1)
    }
}
