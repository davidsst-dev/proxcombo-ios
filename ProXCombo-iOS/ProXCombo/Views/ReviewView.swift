import SwiftUI

struct ReviewView: View {
    @StateObject private var vm: ReviewViewModel

    init(legsRaw: String) {
        _vm = StateObject(wrappedValue: ReviewViewModel(legsRaw: legsRaw))
    }

    var body: some View {
        Group {
            if vm.loading && vm.legs.isEmpty {
                LoadingView()
            } else if let error = vm.error, vm.legs.isEmpty {
                ErrorView(message: error)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        ForEach(Array(vm.legs.enumerated()), id: \.element.id) { index, rl in
                            LegCard(index: index + 1, rl: rl)
                        }
                        TotalsCard(vm: vm)
                        if !vm.alerts.isEmpty {
                            AlertsCard(vm: vm)
                        }
                        if let createError = vm.createError {
                            ErrorCard(message: createError) { vm.retry() }
                        }
                        if let url = vm.createdUrl {
                            ResultCard(vm: vm, url: url)
                        } else {
                            mainButton
                            HStack(spacing: 10) {
                                ShareLink(item: vm.shareText()) {
                                    Label("Compartir", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button(action: { vm.toggleLegLinks() }) {
                                    Text("Abrir cada pierna")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                            if vm.showLegLinks {
                                ForEach(vm.legLinks(), id: \.url) { link in
                                    LegLinkRow(label: link.label, url: link.url)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .background(Theme.paper.ignoresSafeArea())
            }
        }
        .navigationTitle("Revisión")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack {
            Text("Revisión de combinada")
                .font(.title3.bold())
            Spacer()
            if vm.refreshing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Actualizando…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            } else {
                Button(action: { vm.refresh() }) {
                    Label("Refrescar", systemImage: "arrow.clockwise")
                        .font(.subheadline.bold())
                }
                .disabled(vm.legs.isEmpty || vm.creating)
            }
        }
    }

    private var mainButton: some View {
        let anyMarket = vm.legs.contains { $0.market != nil }
        return Button(action: { vm.createComboAndOpen() }) {
            Group {
                if vm.creating {
                    HStack {
                        ProgressView()
                        Text("Creando combinada en Kalshi…")
                    }
                } else if !vm.alerts.isEmpty && !vm.alertsAcknowledged {
                    Text("Entendido, quiero continuar")
                } else if vm.legs.count == 1 {
                    Text("Abrir en Kalshi")
                } else {
                    Text("Crear combinada y abrir Kalshi")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.green)
        .disabled(!anyMarket || vm.creating)
    }
}

// MARK: - Piernas

private struct LegCard: View {
    let index: Int
    let rl: ReviewViewModel.ResolvedLeg

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pierna \(index)")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.green)
                Spacer()
                if rl.inactive {
                    Text("Mercado no activo o partido ya empezado")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            }

            if let error = rl.error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Theme.danger)
            } else {
                let market = rl.market
                Text(market?.displayName ?? rl.leg.ticker)
                    .font(.headline)

                Text(subtitle(market))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                HStack(spacing: 24) {
                    Stat(label: "Precio actual",
                         value: rl.price.map(Format.price) ?? "Sin precio")
                    Stat(label: "Prob. estimada",
                         value: rl.leg.prob.map(Format.percent) ?? "—")
                    Stat(label: "Ventaja",
                         value: rl.advantagePoints.map(Format.points) ?? "—",
                         color: rl.advantagePoints.map { $0 >= 0 ? Theme.green : Theme.danger } ?? Theme.muted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            rl.inactive ? Theme.dangerContainer : Theme.surface,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func subtitle(_ market: Market?) -> String {
        var parts: [String] = []
        parts.append("Partido: " + (market?.event_ticker ?? "—"))
        if let iso = market?.occurrence_datetime, let date = ReviewViewModel.parseIso(iso) {
            let f = DateFormatter()
            f.dateFormat = "dd MMM HH:mm"
            parts.append("Inicio: " + f.string(from: date))
        } else {
            parts.append("Inicio: —")
        }
        parts.append("Estado: " + (market?.status == "active" ? "Activo" : (market?.status ?? "—")))
        return parts.joined(separator: "  ·  ")
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Totales

private struct TotalsCard: View {
    let vm: ReviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Totales de la combinada")
                .font(.caption.bold())
                .foregroundStyle(Theme.muted)
            HStack(spacing: 28) {
                TotalStat(label: "Precio aproximado", value: vm.comboPrice.map(Format.price) ?? "—")
                TotalStat(label: "Probabilidad", value: vm.comboProb.map(Format.percent) ?? "—")
            }
            HStack(spacing: 28) {
                TotalStat(label: "Ventaja",
                          value: vm.comboAdvantage.map(Format.points) ?? "—",
                          color: (vm.comboAdvantage ?? -1) >= 0 ? Theme.greenLight : Color(red: 1, green: 0.44, blue: 0.44))
                TotalStat(label: "Paga", value: vm.pays.map(Format.pays) ?? "—")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(.white)
    }
}

private struct TotalStat: View {
    let label: String
    let value: String
    var color: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Alertas y errores

private struct AlertsCard: View {
    let vm: ReviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Advertencias", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            ForEach(vm.alerts, id: \.self) { alert in
                Text("•  " + alert)
                    .font(.subheadline)
            }
            if !vm.alertsAcknowledged {
                Text("Toca el botón principal para confirmar que quieres continuar.")
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warningContainer, in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(Color(red: 0.47, green: 0.21, blue: 0.06))
    }
}

private struct ErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRetry) {
                Text("Reintentar").font(.subheadline.bold())
            }
        }
        .padding(16)
        .background(Theme.dangerContainer, in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(Color(red: 0.5, green: 0.11, blue: 0.11))
    }
}

// MARK: - Resultado

private struct ResultCard: View {
    let vm: ReviewViewModel
    let url: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Combinada lista", systemImage: "checkmark.seal.fill")
                .font(.title3.bold())
            Text(url)
                .font(.subheadline)
                .lineLimit(2)

            if let realPrice = vm.realPrice {
                Text("Precio real Kalshi: " + Format.price(realPrice))
                    .font(.headline)
                if let adv = vm.realPriceAdvantage {
                    Text("Ventaja de la combinada: " + Format.points(adv))
                        .font(.subheadline)
                }
            }

            let needsConfirm = vm.realPriceAdvantage != nil
                && vm.realPriceAdvantage! < Double(vm.minComboAdvantage)
            if needsConfirm && !vm.realPriceConfirmed {
                Text("Ventaja de la combinada por debajo del mínimo (\(vm.minComboAdvantage) pts)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.danger)
                Button(action: { vm.acknowledgeRealPrice() }) {
                    Text("Entendido, quiero continuar")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.green)
            } else {
                Button(action: { vm.openUrl(url) }) {
                    Label("Abrir en Kalshi", systemImage: "arrow.up.forward.app")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.green)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.greenContainer, in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(Color(red: 0.02, green: 0.35, blue: 0.17))
    }
}

private struct LegLinkRow: View {
    let label: String
    let url: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Link("Abrir", destination: URL(string: url)!)
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Estados

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Consultando precios en Kalshi…")
                .font(.headline)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }
}

private struct ErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.danger)
            Text("No se pudo completar")
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }
}
