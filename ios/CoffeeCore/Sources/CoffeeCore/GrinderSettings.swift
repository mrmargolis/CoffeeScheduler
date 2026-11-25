import Foundation

/// What a grinder's brews say about how it's used: the step usually taken
/// between one brew of a bag and the next, and the range its settings
/// usually fall in.
public struct GrinderHistory: Hashable, Sendable {
    /// The most common change between consecutive brews of one bag; the
    /// smaller on a tie. Nil with too few changes to say.
    public let usualStep: Double?
    /// The 5th to 95th percentile of its settings. Nil with too few brews.
    public let usualRange: ClosedRange<Double>?

    /// Fewer brews than this, and the range isn't worth trusting.
    static let minimumBrews = 10
    /// Fewer changes than this, and neither is the step.
    static let minimumChanges = 3

    /// `runs` is each bag's settings on this grinder, in brew order.
    public init(runs: [[Double]]) {
        let all = runs.flatMap { $0 }
        let places = all.map(Self.decimalPlaces).max() ?? 0
        let changes = runs.flatMap { run in zip(run, run.dropFirst()).map { Self.round(abs($1 - $0), places: places) } }
            .filter { $0 > 0 }
        if changes.count >= Self.minimumChanges {
            let counts = Dictionary(changes.map { ($0, 1) }, uniquingKeysWith: +)
            usualStep = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
        } else {
            usualStep = nil
        }
        if all.count >= Self.minimumBrews {
            let sorted = all.sorted()
            usualRange = Self.percentile(sorted, 0.05)...Self.percentile(sorted, 0.95)
        } else {
            usualRange = nil
        }
    }

    /// Whether a setting falls outside the grinder's usual range, so a
    /// suggestion should give a direction rather than a number.
    public func isUnusual(_ setting: Double) -> Bool {
        usualRange.map { !$0.contains(setting) } ?? false
    }

    /// Nearest rank.
    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        sorted[max(0, Int((p * Double(sorted.count)).rounded(.up)) - 1)]
    }

    /// Decimal places in a setting, up to 2: 1.75 has 2, 4 has 0.
    static func decimalPlaces(_ value: Double) -> Int {
        (0...2).first { Self.round(value, places: $0) == Self.round(value, places: 3) } ?? 2
    }

    static func round(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }
}

/// A grinder's dial-in settings.
public struct GrinderSetting: Hashable, Sendable {
    public let name: String
    /// The step set by hand; nil uses the one from the history.
    public let step: Double?
    public let higherIsCoarser: Bool
    public let history: GrinderHistory

    /// The step suggestions use: the one set, else the usual one. Nil means
    /// suggestions give a direction only.
    public var effectiveStep: Double? { step ?? history.usualStep }
}

extension CoffeeStore {
    // MARK: - Grinder settings

    /// The temperature step suggestions use, in °C.
    public static let defaultTemperatureStep = 2.0

    /// Every grinder in the imported brews, A to Z, with its settings and history.
    public func grinderSettings() throws -> [GrinderSetting] {
        let saved = try savedGrinderSettings()
        let runs = try grindRuns()
        return runs.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { name in
            GrinderSetting(
                name: name, step: saved[name]?.step, higherIsCoarser: saved[name]?.higherIsCoarser ?? true,
                history: GrinderHistory(runs: runs[name] ?? []))
        }
    }

    /// One grinder's settings, or nil for a grinder with no brews.
    public func grinderSetting(_ name: String) throws -> GrinderSetting? {
        try grinderSettings().first { $0.name == name }
    }

    /// Set a grinder's step (nil for the usual one from its history) and direction.
    public func setGrinder(_ name: String, step: Double?, higherIsCoarser: Bool) throws {
        let step = step.flatMap { $0 > 0 ? $0 : nil }
        if step == nil && higherIsCoarser {
            try db.run("DELETE FROM grinder_settings WHERE grinder = ?", [.text(name)])
        } else {
            try db.run(
                "INSERT OR REPLACE INTO grinder_settings (grinder, step, higher_is_coarser) VALUES (?, ?, ?)",
                [.text(name), SQLValue(step), SQLValue(higherIsCoarser)])
        }
    }

    public func temperatureStep() throws -> Double {
        let value = try db.query("SELECT value FROM settings WHERE key = 'dial_in_temperature_step'").first?.string("value")
        return value.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultTemperatureStep
    }

    public func setTemperatureStep(_ step: Double) throws {
        try db.run("INSERT OR REPLACE INTO settings (key, value) VALUES ('dial_in_temperature_step', ?)", [.text(String(step))])
    }

    /// Each grinder's numeric settings, as one run per bag in brew order.
    private func grindRuns() throws -> [String: [[Double]]] {
        var runs: [String: [String: [Double]]] = [:]
        let rows = try db.query(
            """
            SELECT grinder, bean_id, grind_setting FROM brews
            WHERE grinder IS NOT NULL AND grind_setting IS NOT NULL
            ORDER BY creation_date, logged_at, id
            """)
        for row in rows {
            guard let grinder = row.string("grinder"), let bean = row.string("bean_id"),
                let setting = row.string("grind_setting").flatMap(Double.init)
            else { continue }
            runs[grinder, default: [:]][bean, default: []].append(setting)
        }
        return runs.mapValues { Array($0.values) }
    }

    private func savedGrinderSettings() throws -> [String: (step: Double?, higherIsCoarser: Bool)] {
        var saved: [String: (step: Double?, higherIsCoarser: Bool)] = [:]
        for row in try db.query("SELECT * FROM grinder_settings") {
            if let name = row.string("grinder") {
                saved[name] = (row.double("step"), row.int("higher_is_coarser") != 0)
            }
        }
        return saved
    }
}
