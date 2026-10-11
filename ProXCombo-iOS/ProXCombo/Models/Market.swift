import Foundation

/// Mercado de Kalshi (GET /trade-api/v2/markets/{ticker}).
/// Los precios vienen como string "0.4700": se convierten a Double donde se usan.
struct Market: Decodable {
    let ticker: String
    let event_ticker: String
    let title: String?
    let yes_sub_title: String?
    let status: String?
    let yes_ask_dollars: String?
    let yes_bid_dollars: String?
    let no_ask_dollars: String?
    let occurrence_datetime: String?
    let close_time: String?

    /// Título preferido para mostrar: yes_sub_title si existe, si no title, si no ticker.
    var displayName: String {
        if let sub = yes_sub_title, !sub.isEmpty { return sub }
        if let t = title, !t.isEmpty { return t }
        return ticker
    }

    func askPrice(for side: LegCode.Side) -> Double? {
        let raw = (side == .yes) ? yes_ask_dollars : no_ask_dollars
        return raw.flatMap { Double($0) }
    }
}

/// Respuesta de POST /trade-api/v2/multivariate_event_collections/{colección}.
struct ComboCreationResponse: Decodable {
    let event_ticker: String?
    let market_ticker: String?
    let market: MarketPayload?

    struct MarketPayload: Decodable {
        let yes_ask_dollars: String?
    }
}

/// Pierna seleccionada para el body de creación de combinada.
struct SelectedMarket: Encodable {
    let market_ticker: String
    let event_ticker: String
    let side: String
}

/// Body de creación de combinada.
struct ComboCreationRequest: Encodable {
    let selected_markets: [SelectedMarket]
    let with_market_payload: Bool
}
