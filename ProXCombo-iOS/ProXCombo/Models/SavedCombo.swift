import Foundation

/// Combinada guardada en el historial.
struct SavedCombo: Codable, Identifiable, Equatable {
    let id: Int64
    let codeKey: String
    let url: String
    let legsText: String
    let createdAt: Int64
    /// Ventaja de la combinada en pts (nil si no llegó con probabilidad).
    var comboAdvantage: Double?
}
