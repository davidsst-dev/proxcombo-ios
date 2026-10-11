import Foundation

/// Firma de peticiones a Kalshi.
///
/// - mensaje = timestamp + "POST" + path, donde path incluye "/trade-api/v2"
///   y NO incluye query string.
/// - SHA256withRSA/PSS con PSSParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256, 32, 1).
/// - Base64 sin saltos de línea.
///
/// Implementación 100 % en Swift (sin framework Security): parsea el PEM
/// (PKCS#1 "BEGIN RSA PRIVATE KEY" o PKCS#8 "BEGIN PRIVATE KEY"), extrae el
/// módulo `n` y el exponente privado `d`, y calcula `m^d mod n` con
/// aritmética de enteros grandes propia. Equivalente exacto al
/// "SHA256withRSA/PSS" de Android.
enum KalshiSigner {

    // MARK: - API pública

    /// Llave RSA privada: módulo `n` y exponente privado `d`.
    struct RSAKey {
        let n: BigInt
        let d: BigInt
    }

    /// Construye el mensaje a firmar. `path` puede traer query string: se elimina.
    static func buildMessage(timestamp: String, method: String, path: String) -> String {
        let cleanPath = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? path
        return timestamp + method.uppercased() + cleanPath
    }

    /// Carga la llave privada desde PEM.
    /// Acepta PKCS#1 ("BEGIN RSA PRIVATE KEY") y PKCS#8 ("BEGIN PRIVATE KEY").
    static func loadPrivateKey(pem: String) throws -> RSAKey {
        let body = pem
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
        let base64 = body
            .split(whereSeparator: { $0.isWhitespace })
            .joined()
        guard let derData = Data(base64Encoded: base64) else {
            throw KalshiError.invalidKey
        }
        guard let key = parseKey([UInt8](derData)) else {
            throw KalshiError.invalidKey
        }
        return key
    }

    /// Firma `message` con SHA256withRSA/PSS y devuelve Base64 sin saltos de línea.
    static func sign(key: RSAKey, message: String) throws -> String {
        let signature = signPSS(message: Array(message.utf8), key: key)
        return Data(signature).base64EncodedString(options: [])
    }

    /// Firma con timestamp actual (milisegundos). Devuelve (timestamp, signature).
    static func signNow(key: RSAKey, method: String, path: String) throws -> (timestamp: String, signature: String) {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let message = buildMessage(timestamp: timestamp, method: method, path: path)
        let signature = try sign(key: key, message: message)
        return (timestamp, signature)
    }

    // MARK: - DER / PEM

    /// Parser mínimo de DER (TLV).
    private struct DERParser {
        let data: [UInt8]
        var pos = 0

        init(_ data: [UInt8]) {
            self.data = data
        }

        var isAtEnd: Bool { pos >= data.count }

        /// Lee un TLV completo: (tag, valor). Devuelve nil si el DER está mal formado.
        mutating func readTLV() -> (tag: UInt8, value: [UInt8])? {
            guard pos < data.count else { return nil }
            let tag = data[pos]
            pos += 1
            guard pos < data.count else { return nil }
            let first = data[pos]
            pos += 1
            let length: Int
            if first < 0x80 {
                length = Int(first)
            } else {
                let numBytes = Int(first & 0x7F)
                guard numBytes >= 1, numBytes <= 4, pos + numBytes <= data.count else { return nil }
                var len = 0
                for _ in 0..<numBytes {
                    len = (len << 8) | Int(data[pos])
                    pos += 1
                }
                length = len
            }
            guard pos + length <= data.count else { return nil }
            let value = Array(data[pos..<pos + length])
            pos += length
            return (tag, value)
        }
    }

    /// Extrae n y d de un DER PKCS#1 (RSAPrivateKey).
    private static func parsePKCS1(_ der: [UInt8]) -> RSAKey? {
        var parser = DERParser(der)
        guard let outer = parser.readTLV(), outer.tag == 0x30, parser.isAtEnd else {
            return nil
        }
        var inner = DERParser(outer.value)
        var integers: [[UInt8]] = []
        while !inner.isAtEnd {
            guard let tlv = inner.readTLV() else { return nil }
            if tlv.tag == 0x02 {
                integers.append(tlv.value)
            }
        }
        // RSAPrivateKey: version, n, e, d, p, q, dp, dq, qinv
        guard integers.count >= 4 else { return nil }
        let n = BigInt(bytes: integers[1])
        let d = BigInt(bytes: integers[3])
        guard !n.isZero, !d.isZero else { return nil }
        return RSAKey(n: n, d: d)
    }

    /// Extrae n y d de un DER PKCS#8 (PrivateKeyInfo que envuelve PKCS#1).
    private static func parsePKCS8(_ der: [UInt8]) -> RSAKey? {
        var parser = DERParser(der)
        guard let outer = parser.readTLV(), outer.tag == 0x30, parser.isAtEnd else {
            return nil
        }
        var inner = DERParser(outer.value)
        guard let version = inner.readTLV(), version.tag == 0x02 else { return nil }
        guard let alg = inner.readTLV(), alg.tag == 0x30 else { return nil }
        guard let priv = inner.readTLV(), priv.tag == 0x04 else { return nil }
        return parsePKCS1(priv.value)
    }

    private static func parseKey(_ der: [UInt8]) -> RSAKey? {
        if let key = parsePKCS1(der) {
            return key
        }
        return parsePKCS8(der)
    }

    // MARK: - EMSA-PSS (SHA-256, MGF1, salt 32)

    /// Firma `message` con RSA-PSS (SHA-256, MGF1-SHA256, salt 32, trailer 0xBC).
    private static func signPSS(message: [UInt8], key: RSAKey) -> [UInt8] {
        let hashLen = 32
        let saltLen = 32
        let modLen = (key.n.bitLength + 7) / 8
        let emLen = modLen
        guard emLen >= saltLen + hashLen + 2 else {
            return []
        }

        let h = SHA256.hash(message)

        // Salt fijo (32 ceros): Kalshi extrae el salt de la propia firma al
        // verificar, así que cualquier valor es válido; el fijo hace la firma
        // determinista y reproducible.
        let salt = [UInt8](repeating: 0, count: saltLen)

        // RFC 8017 (PKCS#1 v2.2) paso 5: M' = 8 ceros || mHash || salt
        var mPrime = [UInt8](repeating: 0, count: 8)
        mPrime.append(contentsOf: h)
        mPrime.append(contentsOf: salt)

        let hPrime = SHA256.hash(mPrime)

        let dbLen = emLen - hashLen - 1
        let psLen = dbLen - saltLen - 1
        var db = [UInt8](repeating: 0, count: psLen)
        db.append(1)
        db.append(contentsOf: salt)

        var maskedDB = mgf1XOR(db, hPrime, dbLen)

        // Borrar el bit más significativo del primer byte de maskedDB
        // (EM debe tener exactamente emLen bytes).
        maskedDB[0] &= 0x7F

        var em = maskedDB
        em.append(contentsOf: hPrime)
        em.append(0xBC)

        let m = BigInt(bytes: em)
        let s = m.powMod(key.d, key.n)
        return s.toBytes(length: modLen)
    }

    /// db XOR MGF1(seed, len)
    private static func mgf1XOR(_ db: [UInt8], _ seed: [UInt8], _ len: Int) -> [UInt8] {
        var out = db
        var offset = 0
        while offset < len {
            // MGF1 (RFC 8017): el contador es el índice de BLOQUE (0,1,2,...),
            // no el offset de bytes. Cada bloque de SHA-256 tiene 32 bytes.
            let counter = offset / 32
            var c = [UInt8](repeating: 0, count: 4)
            c[0] = UInt8((counter >> 24) & 0xFF)
            c[1] = UInt8((counter >> 16) & 0xFF)
            c[2] = UInt8((counter >> 8) & 0xFF)
            c[3] = UInt8(counter & 0xFF)
            let block = SHA256.hash(seed + c)
            let take = min(block.count, len - offset)
            for i in 0..<take {
                out[offset + i] ^= block[i]
            }
            offset += take
        }
        return out
    }

    // MARK: - SHA-256 (implementación propia)

    private enum SHA256 {
        static let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
            0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
            0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
            0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
            0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
            0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
            0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
            0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        ]

        static func hash(_ message: [UInt8]) -> [UInt8] {
            var h: [UInt32] = [
                0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
            ]

            // Padding
            var data = message
            let bitLen = UInt64(message.count) * 8
            data.append(0x80)
            while data.count % 64 != 56 {
                data.append(0x00)
            }
            for i in (0..<8).reversed() {
                data.append(UInt8((bitLen >> (UInt64(i) * 8)) & 0xFF))
            }

            var w = [UInt32](repeating: 0, count: 64)
            for blockStart in stride(from: 0, to: data.count, by: 64) {
                for t in 0..<16 {
                    let off = blockStart + t * 4
                    w[t] = (UInt32(data[off]) << 24)
                        | (UInt32(data[off + 1]) << 16)
                        | (UInt32(data[off + 2]) << 8)
                        | UInt32(data[off + 3])
                }
                for t in 16..<64 {
                    let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
                    let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
                    w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
                }

                var a = h[0], b = h[1], c = h[2], d = h[3]
                var e = h[4], f = h[5], g = h[6], hh = h[7]

                for t in 0..<64 {
                    let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                    let ch = (e & f) ^ (~e & g)
                    let temp1 = hh &+ s1 &+ ch &+ k[t] &+ w[t]
                    let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                    let maj = (a & b) ^ (a & c) ^ (b & c)
                    let temp2 = s0 &+ maj
                    hh = g; g = f; f = e; e = d &+ temp1
                    d = c; c = b; b = a; a = temp1 &+ temp2
                }

                h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
                h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
            }

            var out = [UInt8]()
            out.reserveCapacity(32)
            for value in h {
                out.append(UInt8((value >> 24) & 0xFF))
                out.append(UInt8((value >> 16) & 0xFF))
                out.append(UInt8((value >> 8) & 0xFF))
                out.append(UInt8(value & 0xFF))
            }
            return out
        }

        private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
            (x >> n) | (x << (32 - n))
        }
    }

    // MARK: - Enteros grandes (mínimo para RSA)

    /// Entero no negativo de precisión arbitraria. Limbs little-endian de 64 bits.
    struct BigInt {
        var limbs: [UInt64]

        init() {
            limbs = [0]
        }

        init(bytes: [UInt8]) {
            // big-endian → little-endian limbs
            var result: [UInt64] = []
            var i = bytes.count - 1
            while i >= 0 {
                var limb: UInt64 = 0
                var shift = 0
                while i >= 0 && shift < 64 {
                    limb |= UInt64(bytes[i]) << shift
                    i -= 1
                    shift += 8
                }
                result.append(limb)
            }
            limbs = result.isEmpty ? [0] : result
            trim()
        }

        var isZero: Bool {
            limbs.allSatisfy { $0 == 0 }
        }

        mutating func trim() {
            while limbs.count > 1 && limbs.last == 0 {
                limbs.removeLast()
            }
        }

        var bitLength: Int {
            guard let top = limbs.last, top > 0 else { return 0 }
            var bits = (limbs.count - 1) * 64
            var t = top
            while t > 0 {
                bits += 1
                t >>= 1
            }
            return bits
        }

        /// Comparación: -1 si self < other, 0 si igual, 1 si self > other.
        func cmp(_ other: BigInt) -> Int {
            if limbs.count != other.limbs.count {
                return limbs.count < other.limbs.count ? -1 : 1
            }
            for i in stride(from: limbs.count - 1, through: 0, by: -1) {
                if limbs[i] != other.limbs[i] {
                    return limbs[i] < other.limbs[i] ? -1 : 1
                }
            }
            return 0
        }

        func add(_ other: BigInt) -> BigInt {
            var result: [UInt64] = []
            result.reserveCapacity(max(limbs.count, other.limbs.count) + 1)
            var carry: UInt64 = 0
            let maxLen = max(limbs.count, other.limbs.count)
            for i in 0..<maxLen {
                let a = i < limbs.count ? limbs[i] : 0
                let b = i < other.limbs.count ? other.limbs[i] : 0
                let sum1 = a &+ b
                let sum2 = sum1 &+ carry
                carry = (sum1 < a ? 1 : 0) | (sum2 < sum1 ? 1 : 0)
                result.append(sum2)
            }
            if carry != 0 {
                result.append(carry)
            }
            var r = BigInt()
            r.limbs = result
            r.trim()
            return r
        }

        /// Resta. Requiere self >= other.
        func sub(_ other: BigInt) -> BigInt {
            var result: [UInt64] = []
            result.reserveCapacity(limbs.count)
            var borrow: UInt64 = 0
            for i in 0..<limbs.count {
                let a = limbs[i]
                let b = i < other.limbs.count ? other.limbs[i] : 0
                let diff1 = a &- b
                let diff2 = diff1 &- borrow
                borrow = (a < b ? 1 : 0) | (diff1 < borrow ? 1 : 0)
                result.append(diff2)
            }
            var r = BigInt()
            r.limbs = result
            r.trim()
            return r
        }

        /// Desplaza a la izquierda 1 bit (multiplica por 2).
        func shiftLeft1() -> BigInt {
            var result: [UInt64] = []
            result.reserveCapacity(limbs.count + 1)
            var carry: UInt64 = 0
            for i in 0..<limbs.count {
                let limb = limbs[i]
                result.append((limb << 1) | carry)
                carry = limb >> 63
            }
            if carry != 0 {
                result.append(carry)
            }
            var r = BigInt()
            r.limbs = result
            r.trim()
            return r
        }

        /// Desplaza a la derecha 1 bit (divide entre 2).
        /// Los limbs son little-endian: el bit bajo del limb siguiente
        /// entra al bit alto del limb actual (lookahead).
        func shiftRight1() -> BigInt {
            var result: [UInt64] = []
            result.reserveCapacity(limbs.count)
            for i in 0..<limbs.count {
                let nextBit = (i + 1 < limbs.count) ? (limbs[i + 1] & 1) : 0
                result.append((limbs[i] >> 1) | (nextBit << 63))
            }
            var r = BigInt()
            r.limbs = result
            r.trim()
            return r
        }

        /// (self + other) mod mod. Requiere self, other < mod.
        func addMod(_ other: BigInt, _ mod: BigInt) -> BigInt {
            let sum = add(other)
            if sum.cmp(mod) >= 0 {
                return sum.sub(mod)
            }
            return sum
        }

        /// (self * 2) mod mod. Requiere self < mod.
        func doubleMod(_ mod: BigInt) -> BigInt {
            let doubled = shiftLeft1()
            if doubled.cmp(mod) >= 0 {
                return doubled.sub(mod)
            }
            return doubled
        }

        /// (self * other) mod mod, por doble-y-suma (sin producto completo).
        func mulMod(_ other: BigInt, _ mod: BigInt) -> BigInt {
            var result = BigInt()
            var a = self
            var b = other
            while !b.isZero {
                if b.limbs[0] & 1 == 1 {
                    result = result.addMod(a, mod)
                }
                a = a.doubleMod(mod)
                b = b.shiftRight1()
            }
            return result
        }

        /// base^exp mod mod (square-and-multiply).
        func powMod(_ exp: BigInt, _ mod: BigInt) -> BigInt {
            var result = BigInt()
            result.limbs = [1]
            var base = self
            var e = exp
            while !e.isZero {
                if e.limbs[0] & 1 == 1 {
                    result = result.mulMod(base, mod)
                }
                base = base.mulMod(base, mod)
                e = e.shiftRight1()
            }
            return result
        }

        /// A bytes big-endian, con relleno a `length`.
        func toBytes(length: Int) -> [UInt8] {
            var bytes: [UInt8] = []
            for i in stride(from: limbs.count - 1, through: 0, by: -1) {
                let limb = limbs[i]
                // big-endian dentro de cada limb: byte alto primero
                for shift in stride(from: 56, through: 0, by: -8) {
                    bytes.append(UInt8((limb >> UInt8(shift)) & 0xFF))
                }
            }
            if bytes.count > length {
                bytes = Array(bytes.suffix(length))
            } else if bytes.count < length {
                bytes = Array(repeating: 0, count: length - bytes.count) + bytes
            }
            return bytes
        }
    }
}
