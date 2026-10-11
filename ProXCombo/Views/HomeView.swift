import SwiftUI

struct HomeView: View {
    let onPaste: () -> Void
    let onSettings: () -> Void
    let onReview: (String) -> Void

    @StateObject private var vm = HomeViewModel()
    @State private var confirmAction: ConfirmAction?

    enum ConfirmAction { case selected, all }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recibe las piernas, revisa los precios y crea la combinada en Kalshi.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                if vm.totalCreated > 0 || vm.bestAdvantage != nil {
                    HStack(spacing: 12) {
                        StatsChip(label: "Total combinadas", value: "\(vm.totalCreated)")
                        StatsChip(label: "Mejor ventaja", value: vm.bestAdvantage.map(Format.points) ?? "—")
                    }
                }

                HStack(spacing: 16) {
                    Button(action: onPaste) {
                        Label("Pegar combinada", systemImage: "doc.on.clipboard")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.green)

                    Button(action: { vm.openForecasts() }) {
                        Label("Ver pronósticos", systemImage: "safari")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Text("Últimas combinadas")
                        .font(.title3.bold())
                    Spacer()
                    Button(action: { vm.toggleSelectionMode() }) {
                        Text(vm.selectionMode ? "Listo" : "Seleccionar")
                            .font(.subheadline.bold())
                    }
                }

                if vm.history.isEmpty {
                    Text("Aún no has abierto ninguna combinada.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    ForEach(vm.history) { combo in
                        HistoryRow(
                            combo: combo,
                            selectionMode: vm.selectionMode,
                            selected: vm.selectedIDs.contains(combo.id),
                            onToggleSelect: { vm.toggleSelect(combo.id) },
                            onOpen: { vm.openUrl(combo.url) },
                            onCopy: { vm.copyLegs(combo) },
                            shareText: vm.shareText(for: combo)
                        )
                    }
                }

                if vm.selectionMode && !vm.selectedIDs.isEmpty {
                    HStack(spacing: 12) {
                        Button(role: .destructive, action: { confirmAction = .selected }) {
                            Label("Eliminar (\(vm.selectedIDs.count))", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: { confirmAction = .all }) {
                            Text("Limpiar todo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("ProX Combo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                }
            }
        }
        .onAppear { vm.refresh() }
        .alert(vm.toast ?? "", isPresented: .init(
            get: { vm.toast != nil },
            set: { if !$0 { vm.consumeToast() } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog(
            confirmAction == .selected ? "¿Eliminar seleccionadas?" : "¿Limpiar todo el historial?",
            isPresented: .init(
                get: { confirmAction != nil },
                set: { if !$0 { confirmAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if confirmAction == .selected {
                Button("Eliminar \(vm.selectedIDs.count)", role: .destructive) {
                    vm.deleteSelected()
                    confirmAction = nil
                }
            } else {
                Button("Limpiar todo", role: .destructive) {
                    vm.clearAllHistory()
                    confirmAction = nil
                }
            }
            Button("Cancelar", role: .cancel) { confirmAction = nil }
        } message: {
            if confirmAction == .selected {
                Text("Se eliminarán \(vm.selectedIDs.count) combinadas del historial.")
            } else {
                Text("Se eliminarán todas las combinadas guardadas.")
            }
        }
    }
}

private struct StatsChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct HistoryRow: View {
    let combo: SavedCombo
    let selectionMode: Bool
    let selected: Bool
    let onToggleSelect: () -> Void
    let onOpen: () -> Void
    let onCopy: () -> Void
    let shareText: String

    var body: some View {
        HStack(spacing: 8) {
            if selectionMode {
                Button(action: onToggleSelect) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Theme.green : Theme.muted)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(Format.date(combo.createdAt))
                    .font(.caption.bold())
                    .foregroundStyle(Theme.green)
                Text(combo.legsText)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
            }

            Button(action: onOpen) {
                Text("Abrir")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            selected ? Theme.greenContainer : Theme.surface,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }
}


