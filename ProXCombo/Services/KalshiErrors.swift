import Foundation

/// Errores de la app con mensajes en español (misma semántica que la app Android).
enum KalshiError: LocalizedError {
    case invalidKey
    case signingFailed
    case blocked(String)
    case noKeys
    case network
    case storageFailed
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Llave privada inválida."
        case .signingFailed:
            return "No se pudo firmar la petición."
        case .blocked(let what):
            return "Petición bloqueada por seguridad: \(what)."
        case .noKeys:
            return "Configura tu Key ID y llave privada en Ajustes."
        case .network:
            return "Sin conexión o error de red."
        case .storageFailed:
            return "No se pudo guardar en el dispositivo."
        case .http(let code, let message):
            let detail = message.isEmpty ? "" : " " + message
            switch code {
            case 401:
                return "Revisa tu Key ID y tu llave de Kalshi."
            case 400:
                return "Kalshi no permite combinar estas piernas." + detail
            case 429:
                return "Demasiadas peticiones. Intenta de nuevo en unos segundos."
            default:
                return "Kalshi respondió con un error (\(code))." + detail
            }
        }
    }
}

/// Credenciales de Kalshi (Key ID + llave privada PEM).
struct Credentials {
    let keyId: String
    let pem: String
}
