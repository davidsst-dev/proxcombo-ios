import Foundation

/// Construcción de URLs de Kalshi (misma lógica que la app Android).
///
/// - serie = parte de event_ticker antes del primer "-", en minúsculas.
/// - url = "https://kalshi.com/markets/" + serie + "/combo/" + event_ticker + "?marketTicker=" + market_ticker
enum ComboUrl {

    /// URL de una combinada creada (o pierna sencilla).
    static func comboUrl(eventTicker: String, marketTicker: String) -> String {
        let serie = series(from: eventTicker)
        return "https://kalshi.com/markets/\(serie)/combo/\(eventTicker)?marketTicker=\(marketTicker)"
    }

    /// URL de una pierna sencilla: ticker = market_ticker.
    static func legUrl(ticker: String, eventTicker: String) -> String {
        comboUrl(eventTicker: eventTicker, marketTicker: ticker)
    }

    /// Parte de event_ticker antes del primer "-", en minúsculas.
    static func series(from eventTicker: String) -> String {
        let head = eventTicker.split(separator: "-").first.map(String.init) ?? eventTicker
        return head.lowercased()
    }

    /// Clave canónica: códigos ordenados unidos por "|".
    static func cacheKey(legs: [LegCode]) -> String {
        legs.map { $0.canonical }.sorted().joined(separator: "|")
    }
}
