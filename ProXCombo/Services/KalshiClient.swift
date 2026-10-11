import Foundation

/// Cliente de la API pública de Kalshi.
///
/// Solo dos operaciones existen en esta app:
///  1. GET  /trade-api/v2/markets/{ticker}                          (pública, sin firma)
///  2. POST /trade-api/v2/multivariate_event_collections/{colección} (firmada)
///
/// - Allowlist: rechaza, sin enviar, cualquier petición fuera de esas dos rutas
///   sobre api.elections.kalshi.com / external-api.kalshi.com.
/// - Reintento exponencial ante 429/5xx (máx. 3: 1 s, 2 s, 4 s). Errores en español.
/// - No existe código para /portfolio, /orders, /communications, /api_keys ni
///   ningún otro endpoint.
final class KalshiClient {

    static let allowedHosts: Set<String> = [
        "api.elections.kalshi.com",
        "external-api.kalshi.com"
    ]

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - API pública

    /// Lee el precio actual de un mercado (público, sin firma).
    func getMarket(base: String, ticker: String) async throws -> Market {
        let url = try allowedURL(base: base, method: "GET", path: "/trade-api/v2/markets/\(ticker)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, http) = try await perform(request)
        guard (200..<300).contains(http.statusCode) else {
            throw KalshiError.http(http.statusCode, extractError(data))
        }
        return try decoder.decode(Market.self, from: data)
    }

    /// Crea la combinada (firmada) y devuelve la respuesta.
    func createCombo(
        base: String,
        collection: String,
        credentials: Credentials,
        selectedMarkets: [SelectedMarket]
    ) async throws -> ComboCreationResponse {
        let path = "/trade-api/v2/multivariate_event_collections/\(collection)"
        let body = ComboCreationRequest(selected_markets: selectedMarkets, with_market_payload: true)
        let (data, http) = try await signedPost(base: base, path: path, body: body, credentials: credentials)
        guard (200..<300).contains(http.statusCode) else {
            throw KalshiError.http(http.statusCode, extractError(data))
        }
        return try decoder.decode(ComboCreationResponse.self, from: data)
    }

    /// "Probar Kalshi": POST a la colección con body {"selected_markets":[]}.
    /// - 400 -> la firma fue aceptada (Conexión correcta).
    /// - 401 -> credenciales incorrectas.
    func testConnection(base: String, collection: String, credentials: Credentials) async throws {
        let path = "/trade-api/v2/multivariate_event_collections/\(collection)"
        let body = ComboCreationRequest(selected_markets: [], with_market_payload: true)
        let (data, http) = try await signedPost(base: base, path: path, body: body, credentials: credentials)
        switch http.statusCode {
        case 200, 400:
            return // 400 = firma correcta: Kalshi rechaza el body vacío.
        case 401:
            throw KalshiError.http(401, "")
        default:
            throw KalshiError.http(http.statusCode, extractError(data))
        }
    }

    // MARK: - Allowlist

    /// Valida host, esquema y ruta exacta ANTES de enviar la petición.
    /// Si algo no coincide, lanza `blocked` sin hacer ninguna llamada de red.
    func allowedURL(base: String, method: String, path: String) throws -> URL {
        let cleanBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: cleanBase + path) else {
            throw KalshiError.blocked("URL inválida")
        }
        guard url.scheme == "https" else {
            throw KalshiError.blocked("solo HTTPS")
        }
        guard let host = url.host?.lowercased(), Self.allowedHosts.contains(host) else {
            throw KalshiError.blocked("host no permitido (\(url.host ?? "sin host"))")
        }
        let cleanPath = url.path
        switch method.uppercased() {
        case "GET":
            guard cleanPath.hasPrefix("/trade-api/v2/markets/"),
                  cleanPath.count > "/trade-api/v2/markets/".count else {
                throw KalshiError.blocked("ruta GET no permitida")
            }
        case "POST":
            guard cleanPath.hasPrefix("/trade-api/v2/multivariate_event_collections/"),
                  cleanPath.count > "/trade-api/v2/multivariate_event_collections/".count else {
                throw KalshiError.blocked("ruta POST no permitida")
            }
        default:
            throw KalshiError.blocked("método no permitido (\(method))")
        }
        return url
    }

    // MARK: - Petición firmada

    private func signedPost(
        base: String,
        path: String,
        body: Encodable,
        credentials: Credentials
    ) async throws -> (Data, HTTPURLResponse) {
        let url = try allowedURL(base: base, method: "POST", path: path)
        guard let key = try? KalshiSigner.loadPrivateKey(pem: credentials.pem) else {
            throw KalshiError.invalidKey
        }
        let (timestamp, signature) = try KalshiSigner.signNow(key: key, method: "POST", path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.keyId, forHTTPHeaderField: "KALSHI-ACCESS-KEY")
        request.setValue(timestamp, forHTTPHeaderField: "KALSHI-ACCESS-TIMESTAMP")
        request.setValue(signature, forHTTPHeaderField: "KALSHI-ACCESS-SIGNATURE")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    // MARK: - Ejecución con reintento

    /// Reintento exponencial ante 429/5xx y fallos de red: 1 s, 2 s, 4 s (máx. 3 reintentos).
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let maxRetries = 3
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw KalshiError.network
                }
                let retryable = (http.statusCode == 429) || (500...599).contains(http.statusCode)
                if retryable {
                    lastError = KalshiError.http(http.statusCode, "")
                } else {
                    return (data, http)
                }
            } catch {
                lastError = error
            }
            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: UInt64(pow(2, Double(attempt))) * 1_000_000_000)
            }
        }
        throw lastError ?? KalshiError.network
    }

    // MARK: - Utilidades

    private func extractError(_ data: Data) -> String {
        struct ErrorEnvelope: Decodable { let error: String? }
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data), let msg = envelope.error {
            return msg
        }
        if let text = String(data: data, encoding: .utf8) {
            return String(text.prefix(200))
        }
        return ""
    }
}
