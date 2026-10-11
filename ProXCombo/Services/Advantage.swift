import Foundation

/// Cálculos de ventaja (misma lógica que la app Android).
///
/// - Ventaja de pierna = prob − precio, expresada en "pts" (centavos).
/// - Precio de la combinada = producto de los precios de las piernas.
/// - Probabilidad de la combinada = producto de las probs (solo si todas vinieron).
/// - "Paga ×" = 1 / precio aproximado.
enum Advantage {

    static func legPoints(prob: Double?, price: Double?) -> Double? {
        guard let prob, let price else { return nil }
        return (prob - price) * 100.0
    }

    static func comboPrice(_ prices: [Double]) -> Double? {
        guard !prices.isEmpty else { return nil }
        return prices.reduce(1.0) { $0 * $1 }
    }

    static func comboProb(_ probs: [Double]) -> Double? {
        guard !probs.isEmpty else { return nil }
        return probs.reduce(1.0) { $0 * $1 }
    }

    static func comboPoints(prob: Double?, price: Double?) -> Double? {
        guard let prob, let price else { return nil }
        return (prob - price) * 100.0
    }

    static func pays(_ price: Double?) -> Double? {
        guard let price, price > 0.0, price < 1.0 else { return nil }
        return 1.0 / price
    }

    /// true si el precio se movió más de `maxMove` (por defecto 0.05 = 5¢) respecto a la prob.
    static func priceMoved(prob: Double?, price: Double?, maxMove: Double = 0.05) -> Bool {
        guard let prob, let price else { return false }
        return abs(price - prob) > maxMove
    }
}
