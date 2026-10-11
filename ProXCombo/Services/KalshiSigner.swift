import Foundation
import Security

/// Firma de peticiones a Kalshi.
///
/// - mensaje = timestamp + "POST" + path, donde path incluye "/trade-api/v2"
///   y NO incluye query string.
/// - SHA256withRSA/PSS con PSSParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256, 32, 1).
/// - Base64 sin saltos de línea.
///
/// La llave privada se carga desde PEM (PKCS#1 "BEGIN RSA PRIVATE KEY" o
/// PKCS#8 "BEGIN PRIVATE KEY") usando el framework Security.
enum KalshiSigner {

    /// Construye el mensaje a firmar. `path` puede traer query string: se elimina.
    static func buildMessage(timestamp: String, method: String, path: String) -> String {
        let cleanPath = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? path
        return timestamp + method.uppercased() + cleanPath
    }

    /// Carga la llave privada desde PEM.
    /// Acepta PKCS#1 (BEGIN RSA PRIVATE KEY) y PKCS#8 (BEGIN PRIVATE KEY).
    static func loadPrivateKey(pem: String) throws -> SecKey {
        let body = pem
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
        let base64 = body
            .split(whereSeparator: { $0.isWhitespace })
            .joined()
        guard let der = Data(base64Encoded: base64) else {
            throw KalshiError.invalidKey
        }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        // kSecFormatOpenSSL maneja la llave (PKCS#1 y PKCS#8); kSecFormatDER como respaldo.
        for format in [kSecFormatOpenSSL, kSecFormatDER] {
            var importError: Unmanaged<CFError>?
            let items = SecItemImport(
                format,
                kSecItemTypeKey,
                [],
                [],
                [],
                attributes as CFDictionary,
                &importError
            )
            if let keys = items as? [SecKey], let key = keys.first {
                return key
            }
        }
        throw KalshiError.invalidKey
    }

    /// Firma `message` con SHA256withRSA/PSS y devuelve Base64 sin saltos de línea.
    ///
    /// `.kSecKeyAlgorithmRSASignaturePSSSHA256` con opciones por defecto produce
    /// exactamente PSSParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256, 32, 1):
    /// digest SHA-256, MGF1-SHA256 y longitud de salt = 32. Equivalente al
    /// "SHA256withRSA/PSS" de Android.
    static func sign(key: SecKey, message: String) throws -> String {
        let messageData = Data(message.utf8)
        guard let signature = SecKeyCreateSignature(
            key,
            .kSecKeyAlgorithmRSASignaturePSSSHA256,
            messageData as CFData,
            [:] as CFDictionary
        ) else {
            throw KalshiError.signingFailed
        }
        return signature.base64EncodedString(options: [])
    }

    /// Firma con timestamp actual (milisegundos). Devuelve (timestamp, signature).
    static func signNow(key: SecKey, method: String, path: String) throws -> (timestamp: String, signature: String) {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let message = buildMessage(timestamp: timestamp, method: method, path: path)
        let signature = try sign(key: key, message: message)
        return (timestamp, signature)
    }
}
