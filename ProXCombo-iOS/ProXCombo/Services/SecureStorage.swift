import Foundation
import Security

/// Almacena la Key ID y la llave privada (PEM) de Kalshi en el **Keychain**.
///
/// Nunca en UserDefaults, logs, Toasts, excepciones ni portapapeles.
/// En pantalla se muestran como "••••" + últimos 4 caracteres.
enum SecureStorage {

    private static let service = "com.proxcombo.ios"
    private static let keyKeyId = "kalshi_key_id"
    private static let keyPem = "kalshi_private_key"

    static func save(keyId: String, pem: String) throws {
        try set(keyId, for: keyKeyId)
        try set(pem, for: keyPem)
    }

    static func load() -> Credentials? {
        guard let keyId = get(keyKeyId), let pem = get(keyPem) else { return nil }
        return Credentials(keyId: keyId, pem: pem)
    }

    static func clear() {
        delete(keyKeyId)
        delete(keyPem)
    }

    static func hasKeys() -> Bool {
        load() != nil
    }

    /// Máscara segura: "••••" + últimos 4 caracteres.
    static func mask(_ value: String) -> String {
        let tail = value.suffix(4)
        return "••••" + tail
    }

    // MARK: - Keychain

    private static func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        SecItemDelete(baseQuery(key) as CFDictionary)
        var query = baseQuery(key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KalshiError.storageFailed
        }
    }

    private static func get(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
