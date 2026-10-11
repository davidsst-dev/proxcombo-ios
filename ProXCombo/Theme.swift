import SwiftUI

/// Paleta estilo Kalshi (azul tinta + verde), misma que la app Android.
enum Theme {
    static let ink = Color(red: 0x0F / 255, green: 0x17 / 255, blue: 0x2A / 255)
    static let green = Color(red: 0x16 / 255, green: 0xA3 / 255, blue: 0x4A / 255)
    static let greenDark = Color(red: 0x15 / 255, green: 0x80 / 255, blue: 0x3D / 255)
    static let greenLight = Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255)
    static let greenContainer = Color(red: 0xDC / 255, green: 0xFC / 255, blue: 0xE7 / 255)
    static let paper = Color(red: 0xF8 / 255, green: 0xFA / 255, blue: 0xFC / 255)
    static let surface = Color.white
    static let muted = Color(red: 0x64 / 255, green: 0x74 / 255, blue: 0x8B / 255)
    static let danger = Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)
    static let dangerContainer = Color(red: 0xFE / 255, green: 0xF2 / 255, blue: 0xF2 / 255)
    static let warning = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
    static let warningContainer = Color(red: 0xFF / 255, green: 0xFB / 255, blue: 0xEB / 255)
}
