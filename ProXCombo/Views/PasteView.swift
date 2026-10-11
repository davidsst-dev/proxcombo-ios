import SwiftUI
import UIKit

struct PasteView: View {
    let onReview: (String) -> Void

    @State private var text: String = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pega los códigos de pierna. Uno por línea, o separados por comas o espacios.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)

                Text("Ejemplo: KXNFLGAME-26OCT18BUFLV-BUF~KXNFLGAME-26OCT18BUFLV~yes~0.770")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                if let error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(Theme.danger)
                }

                HStack(spacing: 12) {
                    Button(action: readClipboard) {
                        Label("Leer portapapeles", systemImage: "clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: review) {
                        Label("Revisar combinada", systemImage: "checkmark.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.green)
                }
                .padding(.vertical, 8)
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Pegar combinada")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func readClipboard() {
        if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
            text = pasted
            error = nil
        } else {
            error = "No se pudo leer el portapapeles."
        }
    }

    private func review() {
        switch LegParser.parse(text) {
        case .success:
            onReview(text)
        case .failure(let message):
            error = message
        }
    }
}
