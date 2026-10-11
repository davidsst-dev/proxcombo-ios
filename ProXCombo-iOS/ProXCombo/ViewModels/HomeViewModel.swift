import Foundation
import Combine
import UIKit

/// Lógica de la pantalla de Inicio:
/// historial con selección/eliminación, estadísticas, copiar y compartir.
final class HomeViewModel: ObservableObject {

    @Published var history: [SavedCombo] = []
    @Published var totalCreated: Int = 0
    @Published var bestAdvantage: Double?
    @Published var selectionMode = false
    @Published var selectedIDs: Set<Int64> = []
    @Published var toast: String?

    private let services = AppServices.shared

    func refresh() {
        history = services.history.history()
        totalCreated = services.history.totalCreated()
        bestAdvantage = history.compactMap { $0.comboAdvantage }.max()
    }

    // MARK: - Selección y eliminación

    func toggleSelectionMode() {
        selectionMode.toggle()
        if !selectionMode { selectedIDs = [] }
    }

    func toggleSelect(_ id: Int64) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func deleteSelected() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        services.history.remove(ids: ids)
        selectedIDs = []
        selectionMode = false
        refresh()
    }

    func clearAllHistory() {
        services.history.clearAll()
        selectedIDs = []
        selectionMode = false
        refresh()
    }

    // MARK: - Copiar y compartir

    func copyLegs(_ combo: SavedCombo) {
        UIPasteboard.general.string = combo.legsText
        toast = "Códigos copiados al portapapeles."
    }

    func shareText(for combo: SavedCombo) -> String {
        var text = "Combinada ProX Combo\n" + combo.legsText
        if let adv = combo.comboAdvantage {
            text += "\nVentaja: " + Format.points(adv)
        }
        text += "\n" + combo.url
        return text
    }

    // MARK: - Navegación

    func openUrl(_ url: String) {
        guard let u = URL(string: url) else { return }
        UIApplication.shared.open(u)
    }

    func openForecasts() {
        let settings = services.settings.load()
        guard let u = URL(string: settings.forecastUrl) else { return }
        UIApplication.shared.open(u)
    }

    func consumeToast() {
        toast = nil
    }
}
