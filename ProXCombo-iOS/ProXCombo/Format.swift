import Foundation

/// Formateadores de la interfaz (estilo Kalshi: precios en decimales, ventajas en pts).
enum Format {

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy · HH:mm"
        return f
    }()

    static func date(_ millis: Int64) -> String {
        dateFmt.string(from: Date(timeIntervalSince1970: Double(millis) / 1000.0))
    }

    /// Precio en dólares: 0.470
    static func price(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    /// Probabilidad: 77.0%
    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100.0)
    }

    /// Ventaja en puntos: +3.5 pts / -1.2 pts
    static func points(_ value: Double) -> String {
        String(format: "%+.1f pts", value)
    }

    /// "Paga ×": ×2.13
    static func pays(_ value: Double) -> String {
        String(format: "×%.2f", value)
    }
}
