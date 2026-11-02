import SwiftUI

/// Detalle de posición (design): key stats, operations for the symbol, Vender / Comprar más.
struct PositionDetailView: View {
    let vm: InvestmentsViewModel
    let holding: HoldingRow
    var onOperate: (OperationType) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(holding.symbol.prefix(4)).font(.footnote.weight(.heavy)).foregroundStyle(VexiaColor.brandBlue)
                        .frame(width: 48, height: 48).background(VexiaColor.tintSoft, in: .rect(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(holding.symbol).font(.title2.weight(.bold))
                        Text([holding.sector.map(SectorNames.label), vm.exchangeLabels(holding.exchanges).first].compactMap { $0?.nilIfEmpty }.joined(separator: " · ").nilIfEmpty ?? (vm.segment == .stocks ? String(localized: "Acción") : String(localized: "Cripto")))
                            .font(.footnote).foregroundStyle(VexiaColor.textSecondary)
                    }
                }
                if let v = holding.value, holding.quantity > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Fmt.money(v / holding.quantity)).font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        Text("precio actual").font(.footnote).foregroundStyle(VexiaColor.textSecondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    stat("Tienes", "\(Fmt.quantity(holding.quantity, crypto: vm.segment == .crypto)) \(vm.segment == .crypto ? holding.symbol : (holding.quantity == 1 ? String(localized: "acción") : String(localized: "acciones")))")
                    stat("Precio promedio", Fmt.money(holding.avgPrice))
                    stat("Valor hoy", holding.value.map { Fmt.money($0) } ?? String(localized: "Sin precio"))
                    stat("Ganancia", holding.gain.map { g in
                        (g >= 0 ? "+" : "−") + Fmt.money(abs(g)) + (holding.gainPercent.map { " · \(Fmt.grouped(abs($0), decimals: 1))%" } ?? "")
                    } ?? "—", color: (holding.gain ?? 0) > 0.005 ? VexiaColor.incomeText : (holding.gain ?? 0) < -0.005 ? VexiaColor.expenseText : .primary)
                }
                let ops = vm.operations(for: holding.symbol)
                if !ops.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Operaciones").font(.headline).padding(.vertical, 10)
                        ForEach(ops, id: \.id) { o in
                            Divider()
                            HStack {
                                Text(o.type.title).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(o.type == .sell ? VexiaColor.expenseText : VexiaColor.incomeText)
                                Text("\(Fmt.grouped(o.qty, decimals: o.qty == o.qty.rounded() ? 0 : 4)) @ \(Fmt.money(o.price))").font(.subheadline)
                                Spacer()
                                Text(Fmt.shortDate(o.date)).font(.caption).foregroundStyle(VexiaColor.textSecondary)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(.background, in: .rect(cornerRadius: 20))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(holding.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button { onOperate(.sell) } label: { Text("Vender").font(.headline).frame(maxWidth: .infinity, minHeight: 34) }
                    .buttonStyle(.glass).tint(VexiaColor.expenseText)
                Button { onOperate(.buy) } label: { Text("Comprar más").font(.headline).frame(maxWidth: .infinity, minHeight: 34) }
                    .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
            .padding(.horizontal).padding(.bottom, 8)
        }
    }

    private func stat(_ k: LocalizedStringKey, _ v: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption).foregroundStyle(VexiaColor.textSecondary)
            Text(v).font(.headline.monospacedDigit()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 16))
    }
}
