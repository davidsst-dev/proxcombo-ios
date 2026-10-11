import SwiftUI

@main
struct ProXComboApp: App {
    var body: some Scene {
        WindowGroup {
            BiometricGate {
                RootView()
            }
            .preferredColorScheme(.light)
        }
    }
}

/// Pantallas de la app (navegación simple con pila).
enum Screen: Hashable {
    case home
    case paste
    case review(legsRaw: String)
    case settings
}

/// Contenedor de servicios (sin frameworks de inyección).
final class AppServices {
    static let shared = AppServices()
    let client = KalshiClient()
    let settings = SettingsStore()
    let history = HistoryStore()
    let cache = ComboCache()
}

struct RootView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                onPaste: { path.append(Screen.paste) },
                onSettings: { path.append(Screen.settings) },
                onReview: { legs in path.append(Screen.review(legsRaw: legs)) }
            )
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .paste:
                    PasteView(onReview: { legs in path.append(Screen.review(legsRaw: legs)) })
                case .review(let legs):
                    ReviewView(legsRaw: legs)
                case .settings:
                    SettingsView()
                case .home:
                    EmptyView()
                }
            }
        }
        .tint(Theme.green)
    }
}
