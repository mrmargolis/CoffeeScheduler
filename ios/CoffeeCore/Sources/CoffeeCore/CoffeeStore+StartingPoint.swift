import Foundation

/// A recipe another bag from the same roaster was dialed in at, to start a
/// new bag from. Shown only; it doesn't feed the advisor.
public struct RoasterStartingPoint: Hashable, Sendable {
    public var beanID: String
    public var beanName: String
    /// The cup marked dialed in, with its recipe.
    public var cup: CupEvaluation
}

extension CoffeeStore {
    /// The newest cup marked dialed in on another bag from this bag's
    /// roaster, matched as roaster defaults are (case and surrounding spaces
    /// don't count). Nil for a bag without a roaster, or when there's none.
    public func roasterStartingPoint(beanID: String) throws -> RoasterStartingPoint? {
        guard
            let roaster = try db.query("SELECT roaster FROM beans WHERE id = ?", [.text(beanID)]).first?.string("roaster")?
                .trimmingCharacters(in: .whitespaces).lowercased(),
            !roaster.isEmpty
        else { return nil }
        let rows = try db.query(
            """
            SELECT e.*, b.name AS bean_name FROM cup_evaluations e JOIN beans b ON b.id = e.bean_id
            WHERE e.verdict = ? AND e.bean_id != ?
            ORDER BY e.evaluated_at DESC, e.id DESC
            """,
            [.text(Verdict.dialedIn.rawValue), .text(beanID)])
        // Trimming and case are matched here, as SQLite's lower() is ASCII only
        let roasters = try Dictionary(
            db.query("SELECT id, roaster FROM beans").compactMap { row in
                row.string("id").map { ($0, (row.string("roaster") ?? "").trimmingCharacters(in: .whitespaces).lowercased()) }
            },
            uniquingKeysWith: { first, _ in first })
        for row in rows {
            guard let cup = Self.evaluation(row), roasters[cup.beanID] == roaster else { continue }
            return RoasterStartingPoint(beanID: cup.beanID, beanName: row.string("bean_name") ?? "", cup: cup)
        }
        return nil
    }
}
