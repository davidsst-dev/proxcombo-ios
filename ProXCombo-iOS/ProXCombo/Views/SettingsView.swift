import SwiftUI

struct SettingsView: View {
    @State private var keyId: String = ""
    @State private var pem: String = ""
    @State private var baseUrl: String = SettingsStore.defaults.baseUrl
    @State private var collection: String = SettingsStore.defaults.collection
    @State private var forecastUrl: String = SettingsStore.defaults.forecastUrl
    @State private var minLeg: String = "4"
    @State private var minCombo: String = "5"

    @State private var saved = false
    @State private var testing = false
    @State private var testResult: TestResult?
    @State private var confirmClear = false
    @State private var error: String?

    enum TestResult: Identifiable {
        case ok
        case bad
        case failure(String)
        var id: String {
            switch self {
            case .ok: return "ok"
            case .bad: return "bad"
            case .failure: return "failure"
            }
        }
    }

    private let services = AppServices.shared

    var body: some View {
        Form {
            // Credenciales
            Section("Credenciales de Kalshi") {
                TextField("Kalshi API Key ID", text: $keyId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Llave privada (PEM)", text: $pem, axis: .vertical)
                    .lineLimit(3...8)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if SecureStorage.hasKeys() {
                    LabeledContent("Guardado", value: "•••• + últimos 4")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }

            // Konfiguración
            Section("Configuración") {
                Picker("Base URL de Kalshi", selection: $baseUrl) {
                    ForEach(SettingsStore.baseURLOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                TextField("Colección de combinadas", text: $collection)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                TextField("URL de la página de pronósticos", text: $forecastUrl)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            // Umbrales
            Section("Umbrales de ventaja") {
                TextField("Ventaja mínima por pierna (pts)", text: $minLeg)
                    .keyboardType(.numberPad)
                TextField("Ventaja mínima de la combinada (pts)", text: $minCombo)
                    .keyboardType(.numberPad)
            }

            // Acciones
            Section {
                Button(action: save) {
                    Text("Guardar cambios").frame(maxWidth: .infinity)
                }
                .disabled(saved)

                Button(action: test) {
                    if testing {
                        HStack {
                            ProgressView()
                            Text("Probando conexión…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Probar Kalshi").frame(maxWidth: .infinity)
                    }
                }
                .disabled(testing)

                Button(role: .destructive, action: { confirmClear = true }) {
                    Text("Borrar todas las claves").frame(maxWidth: .infinity)
                }
            }

            if let testResult {
                Section("Resultado") {
                    switch testResult {
                    case .ok:
                        Label("Conexión correcta: Kalshi aceptó tu firma.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.green)
                    case .bad:
                        Label("Credenciales incorrectas: revisa tu Key ID y tu llave.", systemImage: "xmark.seal.fill")
                            .foregroundStyle(Theme.danger)
                    case .failure(let message):
                        Text("No se pudo probar la conexión: \(message)")
                            .foregroundStyle(Theme.danger)
                    }
                }
            }

            if let error {
                Section {
                    Text(error).foregroundStyle(Theme.danger)
                }
            }
        }
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadCurrent)
        .confirmationDialog(
            "¿Borrar todas las claves?",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("Borrar", role: .destructive) {
                SecureStorage.clear()
                keyId = ""
                pem = ""
                saved = false
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminará la Key ID y la llave privada de este dispositivo.")
        }
    }

    private func loadCurrent() {
        let s = services.settings.load()
        baseUrl = s.baseUrl
        collection = s.collection
        forecastUrl = s.forecastUrl
        minLeg = String(s.minLegAdvantage)
        minCombo = String(s.minComboAdvantage)
        if let creds = SecureStorage.load() {
            keyId = creds.keyId
            pem = creds.pem
        }
    }

    private func save() {
        error = nil
        guard let leg = Int(minLeg), leg >= 0 else {
            error = "Escribe un número válido (0 o mayor)."
            return
        }
        guard let combo = Int(minCombo), combo >= 0 else {
            error = "Escribe un número válido (0 o mayor)."
            return
        }
        let settings = SettingsStore.Settings(
            baseUrl: baseUrl,
            collection: collection,
            forecastUrl: forecastUrl,
            minLegAdvantage: leg,
            minComboAdvantage: combo
        )
        services.settings.save(settings)
        if !keyId.isEmpty && !pem.isEmpty {
            do {
                try SecureStorage.save(keyId: keyId, pem: pem)
            } catch {
                error = error.localizedDescription
                return
            }
        }
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            saved = false
        }
    }

    private func test() {
        guard !testing else { return }
        testing = true
        testResult = nil
        error = nil
        Task { @MainActor in
            do {
                let settings = services.settings.load()
                let keyId = self.keyId
                let pem = self.pem
                guard !keyId.isEmpty, !pem.isEmpty else {
                    testResult = .failure("Configura tu Key ID y tu llave privada.")
                    testing = false
                    return
                }
                let credentials = Credentials(keyId: keyId, pem: pem)
                try await services.client.testConnection(
                    base: settings.baseUrl,
                    collection: settings.collection,
                    credentials: credentials
                )
                testResult = .ok
            } catch {
                if case KalshiError.http(let code, _) = error, code == 401 {
                    testResult = .bad
                } else {
                    testResult = .failure(error.localizedDescription)
                }
            }
            testing = false
        }
    }
}
