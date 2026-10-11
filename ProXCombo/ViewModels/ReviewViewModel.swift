import Foundation
import Combine
import UIKit

/// Pantalla de revisión de la combinada:
///  - consulta el precio actual de cada pierna (en paralelo),
///  - recalcula la ventaja por pierna y de la combinada,
///  - crea la combinada en Kalshi (firmada) o abre la pierna sencilla,
///  - abre la app de Kalshi en esa combinada.
///
/// La app NUNCA coloca órdenes: el usuario aprueba dentro de Kalshi.
final class ReviewViewModel: ObservableObject {

    struct ResolvedLeg: Identifiable {
        let id = UUID()
        let leg: LegCode
        let market: Market?
        let price: Double?
        let advantagePoints: Double?
        let inactive: Bool
        let priceMoved: Bool
        let error: String?
    }

    @Published var loading = true
    @Published var error: String?
    @Published var legs: [ResolvedLeg] = []
    @Published var comboPrice: Double?
    @Published var comboProb: Double?
    @Published var comboAdvantage: Double?
    @Published var pays: Double?
    @Published var alerts: [String] = []
    @Published var alertsAcknowledged = false
    @Published var creating = false
    @Published var createError: String?
    @Published var createdUrl: String?
    @Published var realPrice: Double?
    @Published var realPriceAdvantage: Double?
    @Published var realPriceConfirmed = false
    @Published var minComboAdvantage = 5
    @Published var showLegLinks = false
    @Published var refreshing = false

    private var legsCode: [LegCode] = []
    private let services = AppServices.shared

    init(legsRaw: String) {
        start(legsRaw: legsRaw)
    }

    private func start(legsRaw: String) {
        switch LegParser.parse(legsRaw) {
        case .success(let legs):
            legsCode = legs
            loadPrices()
        case .failure(let message):
            loading = false
            error = message
        }
    }

    // MARK: - Precios y ventajas

    func loadPrices() {
        Task { @MainActor in
            loading = true
            refreshing = true
            error = nil
            let settings = services.settings.load()
            let client = services.client
            let base = settings.baseUrl
            let legsToLoad = legsCode

            let resolved = await withTaskGroup(of: ResolvedLeg.self, returning: [ResolvedLeg].self) { group in
                for leg in legsToLoad {
                    group.addTask {
                        do {
                            let market = try await client.getMarket(base: base, ticker: leg.ticker)
                            return Self.resolveLeg(leg, market)
                        } catch {
                            return ResolvedLeg(
                                leg: leg, market: nil, price: nil, advantagePoints: nil,
                                inactive: false, priceMoved: false, error: error.localizedDescription
                            )
                        }
                    }
                }
                var out: [ResolvedLeg] = []
                for await value in group { out.append(value) }
                return out
            }

            let prices = resolved.compactMap { $0.price }
            let comboPrice = (resolved.count > 0 && prices.count == resolved.count)
                ? Advantage.comboPrice(prices) : nil
            let probs = legsToLoad.compactMap { $0.prob }
            let comboProb = (probs.count == legsToLoad.count) ? Advantage.comboProb(probs) : nil
            let comboAdvantage = Advantage.comboPoints(prob: comboProb, price: comboPrice)
            let builtAlerts = Self.buildAlerts(resolved: resolved, comboAdvantage: comboAdvantage, settings: settings)

            self.legs = resolved
            self.comboPrice = comboPrice
            self.comboProb = comboProb
            self.comboAdvantage = comboAdvantage
            self.pays = Advantage.pays(comboPrice)
            self.alerts = builtAlerts
            self.alertsAcknowledged = false
            self.minComboAdvantage = settings.minComboAdvantage
            self.loading = false
            self.refreshing = false
        }
    }

    /// Refresca los precios sin ocultar la pantalla.
    func refresh() {
        guard !loading, !refreshing, !legs.isEmpty else { return }
        loadPrices()
    }

    static func resolveLeg(_ leg: LegCode, _ market: Market) -> ResolvedLeg {
        let price = market.askPrice(for: leg.side)
        let advantage = Advantage.legPoints(prob: leg.prob, price: price)
        let inactive = (market.status != nil && market.status != "active") ||
            (parseIso(market.occurrence_datetime)?.isBefore(Date()) == true)
        let moved = Advantage.priceMoved(prob: leg.prob, price: price)
        return ResolvedLeg(
            leg: leg, market: market, price: price, advantagePoints: advantage,
            inactive: inactive, priceMoved: moved, error: nil
        )
    }

    static func parseIso(_ value: String?) -> Date? {
        guard let value else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    static func buildAlerts(
        resolved: [ResolvedLeg],
        comboAdvantage: Double?,
        settings: SettingsStore.Settings
    ) -> [String] {
        var alerts: [String] = []
        for rl in resolved {
            if rl.inactive {
                alerts.append("Mercado no activo o partido ya empezado")
            }
            if let adv = rl.advantagePoints, adv < Double(settings.minLegAdvantage) {
                alerts.append("Ventaja de una pierna por debajo del mínimo (\(settings.minLegAdvantage) pts)")
            }
            if rl.priceMoved {
                alerts.append("El mercado se movió más de 5¢ desde la estimación")
            }
        }
        if let comboAdvantage, comboAdvantage < Double(settings.minComboAdvantage) {
            alerts.append("Ventaja de la combinada por debajo del mínimo (\(settings.minComboAdvantage) pts)")
        }
        return Array(Set(alerts)).sorted()
    }

    // MARK: - Crear combinada / abrir Kalshi

    /// Botón principal. Si hay advertencias y aún no se confirmaron,
    /// el primer toque solo las reconoce (segundo toque de confirmación).
    func createComboAndOpen() {
        guard !creating, createdUrl == nil else { return }
        if !alerts.isEmpty && !alertsAcknowledged {
            alertsAcknowledged = true
            return
        }
        Task { @MainActor in
            creating = true
            createError = nil
            do {
                let settings = services.settings.load()
                let resolved = self.legs
                guard !resolved.isEmpty else {
                    throw KalshiError.network
                }
                if resolved.count == 1 {
                    // Una sola pierna: sin POST, abrir directamente.
                    let rl = resolved[0]
                    guard let market = rl.market else { throw KalshiError.network }
                    let eventTicker = market.event_ticker.isEmpty ? rl.leg.eventTicker : market.event_ticker
                    let url = ComboUrl.legUrl(ticker: rl.leg.ticker, eventTicker: eventTicker)
                    try await finish(url: url, realPrice: nil)
                    return
                }
                // Caché de combinadas creadas (24 h).
                if let cached = services.cache.get(legs: legsCode) {
                    try await finish(url: cached, realPrice: nil)
                    return
                }
                guard let credentials = SecureStorage.load() else {
                    throw KalshiError.noKeys
                }
                var selected: [SelectedMarket] = []
                for rl in resolved {
                    guard let market = rl.market else { throw KalshiError.network }
                    let eventTicker = market.event_ticker.isEmpty ? rl.leg.eventTicker : market.event_ticker
                    selected.append(SelectedMarket(
                        market_ticker: rl.leg.ticker,
                        event_ticker: eventTicker,
                        side: rl.leg.side.rawValue
                    ))
                }
                let response = try await services.client.createCombo(
                    base: settings.baseUrl,
                    collection: settings.collection,
                    credentials: credentials,
                    selectedMarkets: selected
                )
                let eventTicker = response.event_ticker?.isEmpty == false
                    ? response.event_ticker! : selected.first!.event_ticker
                let marketTicker = response.market_ticker?.isEmpty == false
                    ? response.market_ticker! : selected.first!.market_ticker
                let url = ComboUrl.comboUrl(eventTicker: eventTicker, marketTicker: marketTicker)
                let realPrice = response.market?.yes_ask_dollars.flatMap { Double($0) }
                    .flatMap { $0 > 0.0 && $0 < 1.0 ? $0 : nil }
                try await finish(url: url, realPrice: realPrice)
            } catch {
                creating = false
                createError = error.localizedDescription
            }
        }
    }

    private func finish(url: String, realPrice: Double?) async {
        var realAdvantage: Double?
        if let realPrice {
            if let comboProb {
                realAdvantage = (comboProb - realPrice) * 100.0
            }
        }
        services.cache.put(legs: legsCode, url: url)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        services.history.add(
            SavedCombo(
                id: now,
                codeKey: ComboUrl.cacheKey(legs: legsCode),
                url: url,
                legsText: legsCode.map { $0.ticker }.joined(separator: "  "),
                createdAt: now,
                comboAdvantage: self.comboAdvantage
            )
        )
        self.createdUrl = url
        self.realPrice = realPrice
        self.realPriceAdvantage = realAdvantage
        self.creating = false
    }

    func openUrl(_ url: String) {
        guard let u = URL(string: url) else {
            createError = "No se encontró ninguna app para abrir ese enlace."
            return
        }
        UIApplication.shared.open(u)
    }

    func toggleLegLinks() {
        showLegLinks.toggle()
    }

    func acknowledgeRealPrice() {
        realPriceConfirmed = true
    }

    func legLinks() -> [(label: String, url: String)] {
        legs.compactMap { rl in
            guard let market = rl.market else { return nil }
            let label = market.displayName.isEmpty ? rl.leg.ticker : market.displayName
            let eventTicker = market.event_ticker.isEmpty ? rl.leg.eventTicker : market.event_ticker
            let url = ComboUrl.legUrl(ticker: rl.leg.ticker, eventTicker: eventTicker)
            return (label, url)
        }
    }

    func retry() {
        creating = false
        createError = nil
        createdUrl = nil
        realPrice = nil
        realPriceAdvantage = nil
        loadPrices()
    }

    // MARK: - Compartir

    func shareText() -> String {
        var text = "Combinada ProX Combo\n" + legsCode.map { $0.ticker }.joined(separator: "  ")
        if let comboPrice {
            text += "\nPrecio aproximado: " + Format.price(comboPrice)
        }
        if let comboAdvantage {
            text += "  ·  Ventaja: " + Format.points(comboAdvantage)
        }
        if let pays {
            text += "  ·  Paga: " + Format.pays(pays)
        }
        if let createdUrl {
            text += "\n" + createdUrl
        }
        return text
    }
}
