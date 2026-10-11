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
        // kSecFormatDER maneja la llave DER (PKCS#1 y PKCS#8); kSecFormatOpenSSL como respaldo.
        for format in [kSecFormatDER, kSecFormatOpenSSL] {
            var importError: Unmanaged<CFError>?
            if let items = SecItemImport(
                format,
                kSecItemTypeKey,
                [],
                [],
                [],
                attributes as CFDictionary,
                &importError
            ) as? [SecKey], let key = items.first {
                return key
            }
        }
        throw KalshiError.invalidKey
    }

    /// Firma `message` con SHA256withRSA/PSS y devuelve Base64 sin saltos de línea.
    static func sign(key: SecKey, message: String) throws -> String {
        let messageData = Data(message.utf8)
        let options: [SecKeyAlgorithm: Any] = [
            .rsaPSSDigestLength: 32,
            .rsaPSSSaltLength: 32,
            .rsaPSSMGF1Hash: SecKeyHashAlgorithm.sha256
        ]
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureSchemePSS,
            messageData as CFData,
            options as CFDictionary
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
