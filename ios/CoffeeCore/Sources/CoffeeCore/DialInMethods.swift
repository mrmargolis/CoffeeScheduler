import Foundation

/// A brew method and whether it gets dial-in advice.
public struct DialInMethod: Hashable, Sendable {
    public let name: String
    public let isOn: Bool
    /// True when the drinker hasn't changed it from the default.
    public let isDefault: Bool
}

/// Which brew methods get dial-in advice. BeanConqueror's method type isn't
/// reliable (a Hario Alpha is a custom preparation), so it goes by name.
public enum DialInMethods {
    /// Names that are on unless turned off: the pour-overs this is tuned for.
    static let defaultNames = ["v60", "hario switch", "hario alpha", "orea"]

    public static func isOnByDefault(_ method: String) -> Bool {
        let name = method.lowercased()
        return defaultNames.contains { name.contains($0) }
    }
}

extension CoffeeStore {
    // MARK: - Dial-in methods

    /// Every method in the imported brews, A to Z, with its setting.
    public func dialInMethods() throws -> [DialInMethod] {
        let overrides = try methodOverrides()
        return try db.query("SELECT DISTINCT method FROM brews WHERE method IS NOT NULL")
            .compactMap { $0.string("method") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { name in
                let override = overrides[name]
                return DialInMethod(name: name, isOn: override ?? DialInMethods.isOnByDefault(name), isDefault: override == nil)
            }
    }

    /// Turn dial-in advice on or off for a method. Setting it back to its
    /// default forgets the override, so a later change of default applies.
    public func setDialIn(method: String, on: Bool) throws {
        if on == DialInMethods.isOnByDefault(method) {
            try db.run("DELETE FROM method_settings WHERE method = ?", [.text(method)])
        } else {
            try db.run("INSERT OR REPLACE INTO method_settings (method, dial_in) VALUES (?, ?)", [.text(method), SQLValue(on)])
        }
    }

    /// Whether a method gets dial-in advice. An unknown method does, since
    /// there's nothing to say it shouldn't.
    public func isDialInMethod(_ method: String?) throws -> Bool {
        guard let method else { return true }
        return try methodOverrides()[method] ?? DialInMethods.isOnByDefault(method)
    }

    /// Whether a bag gets dial-in advice: yes unless every method it's known
    /// to have been brewed with lately (its last 10 brews and its
    /// evaluations) is turned off.
    public func bagUsesDialInMethod(beanID: String) throws -> Bool {
        let brewMethods = try db.query(
            "SELECT method FROM brews WHERE bean_id = ? ORDER BY creation_date DESC, logged_at DESC, id DESC LIMIT 10",
            [.text(beanID)]
        ).compactMap { $0.string("method") }
        let evaluated = try evaluations(beanID: beanID).compactMap(\.recipe.brew.method)
        let methods = Set(brewMethods + evaluated)
        guard !methods.isEmpty else { return true }
        return try methods.contains { try isDialInMethod($0) }
    }

    private func methodOverrides() throws -> [String: Bool] {
        var overrides: [String: Bool] = [:]
        for row in try db.query("SELECT method, dial_in FROM method_settings") {
            if let method = row.string("method") { overrides[method] = row.int("dial_in") == 1 }
        }
        return overrides
    }
}
