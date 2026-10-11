import Foundation

/// Una pierna de la combinada.
/// - `eventTicker` puede ser un valor provisional (igual que `ticker`) cuando la
///   entrada solo trae el ticker; el valor real lo devuelve la API al consultar el mercado.
struct LegCode: Equatable, Codable {
    enum Side: String, Codable {
        case yes
        case no
    }

    let ticker: String
    let eventTicker: String
    let side: Side
    let prob: Double?

    /// Código canónico para la caché de combinadas creadas.
    var canonical: String { "\(ticker)~\(eventTicker)~\(side.rawValue)" }
}

/// Parser de "códigos de pierna".
///
/// Formato: TICKER~EVENT_TICKER~LADO~PROB
///   - LADO: "yes" o "no"
///   - PROB (0-1) opcional; puede venir vacío
/// También se acepta una línea con SOLO el ticker:
///   - event_ticker se obtiene después de la API, lado = "yes" y sin prob.
///
/// Separadores aceptados entre piernas: salto de línea, coma o espacios.
/// Validación:
///   - ticker y event_ticker solo con [A-Z0-9-]
///   - máximo 6 piernas
///   - event_tickers distintos entre sí (si se repite: "Dos piernas del mismo partido")
enum LegParser {

    static let maxLegs = 6

    enum ParseResult {
        case success([LegCode])
        case failure(String)
    }

    static func parse(_ raw: String) -> ParseResult {
        let tokens = splitTokens(raw)
        if tokens.isEmpty {
            return .failure("Pega al menos una pierna.")
        }
        if tokens.count > maxLegs {
            return .failure("Máximo 6 piernas.")
        }
        var legs: [LegCode] = []
        for token in tokens {
            guard let leg = parseToken(token) else {
                return .failure("Código de pierna inválido: \(token)")
            }
            legs.append(leg)
        }
        // Duplicados por event_ticker.
        var counts: [String: Int] = [:]
        for leg in legs {
            counts[leg.eventTicker, default: 0] += 1
        }
        if counts.values.contains(where: { $0 > 1 }) {
            return .failure("Dos piernas del mismo partido")
        }
        return .success(legs)
    }

    /// Separa por líneas, comas y espacios (uno o varios).
    static func splitTokens(_ raw: String) -> [String] {
        let separators = CharacterSet.whitespaces
            .union(.newlines)
            .union(CharacterSet(charactersIn: ","))
        return raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseToken(_ token: String) -> LegCode? {
        let parts = token.components(separatedBy: "~").map { $0.trimmingCharacters(in: .whitespaces) }
        switch parts.count {
        case 1:
            let ticker = parts[0].uppercased()
            guard isTicker(ticker) else { return nil }
            return LegCode(ticker: ticker, eventTicker: ticker, side: .yes, prob: nil)
        case 3:
            let ticker = parts[0].uppercased()
            let event = parts[1].uppercased()
            guard let side = parseSide(parts[2]), isTicker(ticker), isTicker(event) else { return nil }
            return LegCode(ticker: ticker, eventTicker: event, side: side, prob: nil)
        case 4:
            let ticker = parts[0].uppercased()
            let event = parts[1].uppercased()
            guard let side = parseSide(parts[2]), isTicker(ticker), isTicker(event) else { return nil }
            let prob: Double?
            if parts[3].isEmpty {
                prob = nil
            } else {
                guard let value = Double(parts[3]), value >= 0.0, value <= 1.0 else { return nil }
                prob = value
            }
            return LegCode(ticker: ticker, eventTicker: event, side: side, prob: prob)
        default:
            return nil
        }
    }

    private static func parseSide(_ raw: String) -> LegCode.Side? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "yes": return .yes
        case "no": return .no
        default: return nil
        }
    }

    static func isTicker(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
