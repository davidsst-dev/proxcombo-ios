import SwiftUI
import LocalAuthentication

/// Bloqueo biométrico al abrir y al volver tras 5 minutos en segundo plano.
///
/// - Si el dispositivo tiene Face ID / Touch ID, exige autenticación.
/// - Si no hay biometría, desbloquea directamente (el sistema sigue protegiendo el dispositivo).
struct BiometricGate<Content: View>: View {
    let content: () -> Content
    @Environment(\.scenePhase) private var scenePhase
    @State private var locked = true
    @State private var authMessage: String?
    @State private var lastBackground: Date?

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            content()
                .opacity(locked ? 0 : 1)
                .allowsHitTesting(!locked)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .background {
                        lastBackground = Date()
                    } else if newPhase == .active {
                        if let last = lastBackground, Date().timeIntervalSince(last) > 300 {
                            locked = true
                        }
                    }
                }

            if locked {
                LockView(message: authMessage) {
                    authenticate()
                }
                .transition(.opacity)
            }
        }
        .onAppear { authenticate() }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        let reason = "Para abrir ProX Combo"
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        withAnimation { locked = false }
                    }
                }
            }
        } else {
            // Sin biometría registrada: desbloquear.
            withAnimation { locked = false }
        }
    }
}

private struct LockView: View {
    let message: String?
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.greenLight)
                Text("ProX Combo")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text("Sesión bloqueada")
                    .font(.headline)
                    .foregroundStyle(Theme.muted)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.warning)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Button(action: onUnlock) {
                    Text("Desbloquear")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.green)
                .padding(.top, 8)
                .frame(maxWidth: 280)
            }
            .padding(32)
        }
    }
}
