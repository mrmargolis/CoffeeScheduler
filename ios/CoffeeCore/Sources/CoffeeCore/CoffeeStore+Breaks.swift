import Foundation

/// Breaks in a bag: where it stops, and where the rest of it waits in the queue.
extension CoffeeStore {
    /// Break the bag once `afterGrams` of it are used. The rest is queued
    /// after the bag that follows, until it's dragged elsewhere.
    @discardableResult
    public func addBreak(beanID: String, afterGrams: Double) throws -> Int {
        try validateBreak(beanID: beanID, afterGrams: afterGrams, except: nil)
        try db.run("INSERT INTO breaks (bean_id, after_grams) VALUES (?, ?)", [.text(beanID), .double(afterGrams)])
        return try db.query("SELECT last_insert_rowid() AS id").first?.int("id") ?? 0
    }

    /// Move where a break comes in the bag, keeping the rest's place in the queue.
    public func updateBreak(id: Int, afterGrams: Double) throws {
        guard let beanID = try db.query("SELECT bean_id FROM breaks WHERE id = ?", [.int(Int64(id))]).first?.string("bean_id")
        else { throw BreakError.notFound }
        try validateBreak(beanID: beanID, afterGrams: afterGrams, except: id)
        try db.run("UPDATE breaks SET after_grams = ? WHERE id = ?", [.double(afterGrams), .int(Int64(id))])
    }

    /// End a break: the bag is drunk straight on.
    public func deleteBreak(id: Int) throws {
        try db.transaction {
            try db.run("DELETE FROM breaks WHERE id = ?", [.int(Int64(id))])
            try resequenceDisplayOrder()
        }
    }

    private func validateBreak(beanID: String, afterGrams: Double, except id: Int?) throws {
        guard let weight = try db.query("SELECT weight_grams FROM beans WHERE id = ?", [.text(beanID)]).first?.double("weight_grams")
        else { throw BreakError.notFound }
        guard afterGrams > 0, afterGrams < weight else { throw BreakError.outOfRange(weightGrams: weight) }
        let others = try db.query("SELECT id, after_grams FROM breaks WHERE bean_id = ?", [.text(beanID)])
            .filter { $0.int("id") != id }
            .compactMap { $0.double("after_grams") }
        if others.contains(where: { abs($0 - afterGrams) < 1 }) { throw BreakError.alreadyThere }
    }
}

public enum BreakError: LocalizedError, Equatable {
    case notFound
    case outOfRange(weightGrams: Double)
    case alreadyThere

    public var errorDescription: String? {
        switch self {
        case .notFound: "That bag or break is no longer in the database."
        case .outOfRange(let weight): "A break has to leave some of the bag's \(Int(weight)) g on each side of it."
        case .alreadyThere: "The bag already has a break there."
        }
    }
}
