import Testing

@testable import CoffeeCore

@Suite struct QueueOrderTests {
    let store: CoffeeStore

    /// b1...b4, roasted a day apart, none manually ordered.
    init() throws {
        store = try CoffeeStore.inMemory()
        for (i, id) in ["b1", "b2", "b3", "b4"].enumerated() {
            try store.db.run(
                "INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived) VALUES (?, 'Bean', 'Roaster', ?, 250, 0)",
                [.text(id), .text("2026-01-0\(i + 1)")]
            )
        }
    }

    func orders() throws -> [String: Int] {
        var result: [String: Int] = [:]
        for row in try store.db.query("SELECT id, display_order FROM beans WHERE display_order IS NOT NULL") {
            result[row.string("id")!] = row.int("display_order")
        }
        return result
    }

    func queue() throws -> [String] {
        try store.beans(archived: false, today: "2026-02-01").map(\.id)
    }

    @Test func numbersTheQueueInOrder() throws {
        try store.reorderQueue(["b3", "b1", "b4", "b2"])
        #expect(try orders() == ["b3": 1, "b1": 2, "b4": 3, "b2": 4])
        #expect(try queue() == ["b3", "b1", "b4", "b2"])
    }

    @Test func moveAgainRenumbers() throws {
        try store.reorderQueue(["b3", "b1", "b4", "b2"])
        try store.reorderQueue(["b1", "b3", "b4", "b2"])
        #expect(try orders() == ["b1": 1, "b3": 2, "b4": 3, "b2": 4])
    }

    @Test func otherOrderedBagsFollowWithoutTies() throws {
        // b4 is ordered but not part of the list passed in (an emptied bag, say)
        try store.db.run("UPDATE beans SET display_order = 1 WHERE id = 'b4'")
        try store.reorderQueue(["b2", "b1"])
        #expect(try orders() == ["b2": 1, "b1": 2, "b4": 3])
    }

    @Test func scheduleFollowsManualOrder() throws {
        try store.reorderQueue(["b4", "b3", "b2", "b1"])
        let first = try store.schedule(start: "2026-03-01", end: "2026-03-01", today: "2026-03-01")
        #expect(first.first?.consumptions.first?.beanID == "b4")
    }

    @Test func clearingOneBagResequencesTheRest() throws {
        try store.reorderQueue(["b3", "b1", "b4", "b2"])
        try store.clearQueuePosition(id: "b1")
        #expect(try orders() == ["b3": 1, "b4": 2, "b2": 3])
        // Unordered bags come after the ordered ones
        #expect(try queue() == ["b3", "b4", "b2", "b1"])
    }

    @Test func clearingTheWholeOrder() throws {
        try store.reorderQueue(["b3", "b1", "b4", "b2"])
        try store.clearQueueOrder()
        #expect(try orders().isEmpty)
        #expect(try queue() == ["b1", "b2", "b3", "b4"])
    }
}
