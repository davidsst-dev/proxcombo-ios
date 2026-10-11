import Foundation

/// Ajustes no sensibles (UserDefaults).
/// Las credenciales (Key ID, PEM) viven en SecureStorage (Keychain).
final class SettingsStore {

    struct Settings {
        var baseUrl: String
        var collection: String
        var forecastUrl: String
        var minLegAdvantage: Int
        var minComboAdvantage: Int
    }

    static let baseURLOptions = [
        "https://api.elections.kalshi.com",
        "https://external-api.kalshi.com"
    ]

    static let defaults = Settings(
        baseUrl: "https://api.elections.kalshi.com",
        collection: "KXMVECROSSCATEGORY-SHARD1-R",
        forecastUrl: "https://claude.ai/artifact/K3XocKFFBGNEnPBK5nvTKr",
        minLegAdvantage: 4,
        minComboAdvantage: 5
    )

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let baseUrl = "settings.baseUrl"
        static let collection = "settings.collection"
        static let forecastUrl = "settings.forecastUrl"
        static let minLeg = "settings.minLeg"
        static let minCombo = "settings.minCombo"
    }

    func load() -> Settings {
        Settings(
            baseUrl: defaults.string(forKey: Keys.baseUrl) ?? SettingsStore.defaults.baseUrl,
            collection: defaults.string(forKey: Keys.collection) ?? SettingsStore.defaults.collection,
            forecastUrl: defaults.string(forKey: Keys.forecastUrl) ?? SettingsStore.defaults.forecastUrl,
            minLegAdvantage: defaults.object(forKey: Keys.minLeg) as? Int ?? SettingsStore.defaults.minLegAdvantage,
            minComboAdvantage: defaults.object(forKey: Keys.minCombo) as? Int ?? SettingsStore.defaults.minComboAdvantage
        )
    }

    func save(_ s: Settings) {
        defaults.set(s.baseUrl, forKey: Keys.baseUrl)
        defaults.set(s.collection, forKey: Keys.collection)
        defaults.set(s.forecastUrl, forKey: Keys.forecastUrl)
        defaults.set(s.minLegAdvantage, forKey: Keys.minLeg)
        defaults.set(s.minComboAdvantage, forKey: Keys.minCombo)
    }
}

/// Historial de combinadas (últimas 10) + contador acumulado.
final class HistoryStore {

    private let defaults = UserDefaults.standard
    private let keyHistory = "history.json"
    private let keyTotal = "history.total"
    static let maxItems = 10

    func history() -> [SavedCombo] {
        guard let data = defaults.data(forKey: keyHistory) else { return [] }
        return (try? JSONDecoder().decode([SavedCombo].self, from: data)) ?? []
    }

    func totalCreated() -> Int {
        defaults.integer(forKey: keyTotal)
    }

    @discardableResult
    func add(_ combo: SavedCombo) -> [SavedCombo] {
        var current = history()
        current.removeAll { $0.id == combo.id }
        current.append(combo)
        current.sort { $0.id > $1.id }
        let trimmed = Array(current.prefix(Self.maxItems))
        save(trimmed)
        defaults.set(defaults.integer(forKey: keyTotal) + 1, forKey: keyTotal)
        return trimmed
    }

    func remove(ids: Set<Int64>) {
        let remaining = history().filter { !ids.contains($0.id) }
        save(remaining)
    }

    func clearAll() {
        save([])
    }

    private func save(_ combos: [SavedCombo]) {
        if let data = try? JSONEncoder().encode(combos) {
            defaults.set(data, forKey: keyHistory)
        }
    }
}

/// Caché de combinadas creadas (24 h).
final class ComboCache {

    private struct Entry: Codable {
        let url: String
        let createdAt: Int64
    }

    private let defaults = UserDefaults.standard
    private let prefix = "combo_cache."
    static let ttl: Int64 = 24 * 60 * 60 * 1000

    func get(legs: [LegCode]) -> String? {
        let key = prefix + ComboUrl.cacheKey(legs: legs)
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if now - entry.createdAt > Self.ttl {
            defaults.removeObject(forKey: key)
            return nil
        }
        return entry.url
    }

    func put(legs: [LegCode], url: String) {
        let key = prefix + ComboUrl.cacheKey(legs: legs)
        let entry = Entry(url: url, createdAt: Int64(Date().timeIntervalSince1970 * 1000))
        if let data = try? JSONEncoder().encode(entry) {
            defaults.set(data, forKey: key)
        }
    }
}
