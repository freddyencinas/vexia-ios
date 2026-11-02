import SwiftUI
import Charts

/// Inversiones (design: market selector in the title, neutral zero, view chips, exchange filter, rich empty state).
struct InvestmentsView: View {
    @Environment(ActivityIslandCenter.self) private var island: ActivityIslandCenter?
    @State var vm: InvestmentsViewModel
    @Binding var showNewOperation: Bool
    @Environment(\.container) private var container
    @State private var formRequest: FormRequest?

    struct FormRequest: Identifiable {
        let id = UUID(); var holding: HoldingRow?; var operation: OperationType = .buy
        var editingStock: Investment?; var editingCrypto: CryptoTransaction?
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                hero
                if vm.segment == .crypto && !vm.exchanges.isEmpty { exchangeChips }
                if !vm.loadedOnce {
                    ForEach(0..<3, id: \.self) { _ in holdingRow(Self.placeholder).redacted(reason: .placeholder) }
                } else if vm.holdings.isEmpty && vm.stockOps.isEmpty && vm.cryptoOps.isEmpty {
                    emptyState
                } else {
                    viewChips
                    content
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(vm.segment.title)
        .navigationBarTitleDisplayMode(.inline) // shows the title-menu chevron (market switch)
        .toolbarTitleMenu {
            ForEach(InvestmentsViewModel.Segment.allCases) { s in
                Button { vm.segment = s } label: { Label(s.title, systemImage: s == .stocks ? "building.2" : "bitcoinsign.circle") }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Actualizar precios", systemImage: "arrow.triangle.2.circlepath") {
                    Task {
                        if let island { await island.run(vm.updatingPricesTitle) { await vm.updatePrices() } }
                        else { _ = await vm.updatePrices() }
                    }
                }
                .disabled(island?.isWorking == true)
            }
        }
        .refreshable { await vm.load() }
        .task { if !vm.loadedOnce { await vm.load() } }
        .onChange(of: vm.segment) { vm.exchange = nil; vm.tab = .portfolio; Task { await vm.load() } }
        .onChange(of: showNewOperation) { _, new in if new { formRequest = FormRequest(); showNewOperation = false } }
        .navigationDestination(for: HoldingRow.self) { h in
            PositionDetailView(vm: vm, holding: h) { op in formRequest = FormRequest(holding: h, operation: op) }
        }
        .sheet(item: $formRequest) { req in
            InvestmentFormView(vm: InvestmentFormViewModel(isCrypto: vm.segment == .crypto, stocks: vm.stocksRepo, crypto: vm.cryptoRepo,
                                                           catalog: container?.catalog, holding: req.holding, operation: req.operation,
                                                           editingStock: req.editingStock, editingCrypto: req.editingCrypto)) {
                Task { await vm.load() }
            }
        }
        .errorAlert($vm.errorMessage)
    }

    // MARK: Hero

    private var hero: some View {
        let h = vm.headline
        let isZero = abs(h.gain) < 0.005
        return VStack(alignment: .leading, spacing: 8) {
            Text(vm.exchange.map { String(localized: "Valor actual · \($0)") } ?? String(localized: "Valor actual")).font(.footnote).foregroundStyle(Color(hex: 0xD6DEF5))
            Text(Fmt.money(h.value)).font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
            HStack {
                Text("Invertido \(Fmt.money(h.invested, compact: true))").font(.footnote).foregroundStyle(Color(hex: 0xD6DEF5))
                Spacer()
                Text(isZero ? String(localized: "Sin variación · 0%") : "\(h.gain > 0 ? "▲" : "▼") \(Fmt.money(abs(h.gain))) · \(Fmt.grouped(abs(h.percent), decimals: 1))%")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isZero ? Color(hex: 0xD6DEF5) : (h.gain > 0 ? Color(hex: 0x9FE6C8) : Color(hex: 0xFFB4AB)))
            }
            let alloc = vm.allocation
            if !alloc.isEmpty {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(alloc.enumerated()), id: \.offset) { i, a in
                            Capsule().fill(Self.allocColors[i % Self.allocColors.count]).frame(width: max(4, BarMetrics.width(g.size.width, a.share) - 2))
                        }
                    }
                }
                .frame(height: 8)
                HStack(spacing: 10) {
                    ForEach(Array(alloc.prefix(3).enumerated()), id: \.offset) { i, a in
                        HStack(spacing: 4) {
                            Circle().fill(Self.allocColors[i % Self.allocColors.count]).frame(width: 7, height: 7)
                            Text("\(a.label) \(Fmt.percent(a.share * 100))")
                        }
                    }
                }
                .font(.caption).foregroundStyle(Color(hex: 0xD6DEF5)).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VexiaColor.brandFill, in: .rect(cornerRadius: 22))
    }

    static let allocColors: [Color] = [Color(hex: 0x8FA8F0), Color(hex: 0x9FE6C8), Color(hex: 0xF7C873), Color(hex: 0xF2A7C3)]

    // MARK: Chips

    private var viewChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(InvestmentsViewModel.Tab.allCases) { t in
                    chip(t.title, vm.tab == t) { vm.tab = t }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var exchangeChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(String(localized: "Todas"), vm.exchange == nil) { vm.exchange = nil }
                ForEach(vm.exchanges, id: \.self) { e in chip(e, vm.exchange == e) { vm.exchange = e } }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 36)
                .background(on ? VexiaColor.brandFill : Color(.secondarySystemGroupedBackground), in: .capsule)
                .foregroundStyle(on ? .white : .primary)
                .overlay(Capsule().strokeBorder(on ? .clear : Color(.separator)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch vm.tab {
        case .portfolio:
            card {
                if vm.holdings.isEmpty { emptyRow("Sin posiciones abiertas") }
                ForEach(Array(vm.holdings.enumerated()), id: \.element.id) { i, h in
                    if i > 0 { Divider() }
                    NavigationLink(value: h) { holdingRow(h) }.buttonStyle(.plain)
                }
            }
        case .pnl: pnlSection
        case .sales:
            card {
                if vm.sales.isEmpty { emptyRow("Aún no has vendido") }
                ForEach(Array(vm.sales.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { Divider() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vendiste \(Fmt.grouped(s.quantity, decimals: s.quantity == s.quantity.rounded() ? 0 : 4)) \(s.symbol)").font(.subheadline.weight(.semibold))
                            Text([s.saleDate.map(Fmt.shortDate), String(localized: "a \(Fmt.money(s.salePrice))", comment: "Sale price, as in 'at $10'"), String(localized: "costo \(Fmt.money(s.costBasis))", comment: "Cost basis")].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(VexiaColor.textSecondary)
                        }
                        Spacer()
                        gainLabel(s.realizedPnL, s.realizedPnLPercent)
                    }
                    .padding(.vertical, 10)
                }
            }
        case .operations:
            card {
                let ops = vm.operationRows
                if ops.isEmpty { emptyRow("Sin operaciones") }
                ForEach(Array(ops.enumerated()), id: \.element.id) { i, o in
                    if i > 0 { Divider() }
                    Button { openEdit(id: o.id) } label: {
                        HStack(spacing: 12) {
                            Text(o.type == .sell ? String(localized: "VENTA") : o.type == .buy ? String(localized: "COMPRA") : String(localized: "MANTENER")).font(.caption2.weight(.bold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(o.type == .sell ? VexiaColor.redSoft : VexiaColor.greenSoft, in: .rect(cornerRadius: 6))
                                .foregroundStyle(o.type == .sell ? VexiaColor.expenseText : VexiaColor.incomeText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Fmt.grouped(o.qty, decimals: o.qty == o.qty.rounded() ? 0 : 4)) \(o.sym)").font(.subheadline.weight(.semibold))
                                Text(o.fee > 0 ? String(localized: "\(Fmt.shortDate(o.date)) · \(Fmt.money(o.price)) c/u · comisión \(Fmt.money(o.fee))")
                                                       : String(localized: "\(Fmt.shortDate(o.date)) · \(Fmt.money(o.price)) c/u"))
                                    .font(.caption).foregroundStyle(VexiaColor.textSecondary)
                            }
                            Spacer()
                            Text(Fmt.money(o.qty * o.price)).font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { deleteOp(id: o.id) } label: { Label("Eliminar", systemImage: "trash") }
                    }
                }
            }
        }
    }

    private var pnlSection: some View {
        let list = vm.filteredPnL
        let maxAbs = vm.pnlMaxAbsPercent
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                statTile("No realizado", vm.pnlUnrealizedTotal)
                statTile("Realizado (ventas)", vm.pnlRealizedTotal)
            }
            card {
                if list.isEmpty { emptyRow("Sin datos de ganancias todavía") }
                ForEach(list) { p in
                    HStack(spacing: 10) {
                        Text(p.symbol).font(.footnote.weight(.bold)).frame(width: 52, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(Color(.secondarySystemBackground)).overlay(alignment: .leading) {
                                Capsule().fill(p.pnl >= 0 ? VexiaColor.brandGreen : VexiaColor.expenseFill)
                                    .frame(width: BarMetrics.width(g.size.width, abs(p.pnlPercent) / maxAbs))
                            }
                        }
                        .frame(height: 10)
                        Text((p.pnlPercent >= 0 ? "+" : "−") + Fmt.grouped(abs(p.pnlPercent), decimals: 1) + "%")
                            .font(.footnote.weight(.semibold).monospacedDigit()).frame(width: 64, alignment: .trailing)
                            .foregroundStyle(abs(p.pnlPercent) < 0.05 ? VexiaColor.textSecondary : (p.pnl >= 0 ? VexiaColor.incomeText : VexiaColor.expenseText))
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func statTile(_ title: LocalizedStringKey, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(VexiaColor.textSecondary)
            Text((v > 0 ? "+" : "") + Fmt.money(v)).font(.headline.monospacedDigit())
                .foregroundStyle(abs(v) < 0.005 ? .primary : (v > 0 ? VexiaColor.incomeText : VexiaColor.expenseText))
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 18))
    }

    func holdingRow(_ h: HoldingRow) -> some View {
        HStack(spacing: 12) {
            Text(h.symbol.prefix(4)).font(.caption.weight(.heavy))
                .foregroundStyle(h.isStablecoin ? VexiaColor.brandGreen : VexiaColor.brandBlue)
                .frame(width: 42, height: 42)
                .background(h.isStablecoin ? VexiaColor.greenSoft : VexiaColor.tintSoft, in: vm.segment == .crypto ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(h.symbol).font(.body.weight(.semibold))
                    ForEach(vm.exchangeLabels(h.exchanges).prefix(2), id: \.self) { e in
                        Text(e).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 5)).foregroundStyle(VexiaColor.textSecondary)
                    }
                }
                Text("\(Fmt.quantity(h.quantity, crypto: vm.segment == .crypto)) · prom. \(Fmt.money(h.avgPrice))")
                    .font(.caption).foregroundStyle(VexiaColor.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.money(h.value ?? h.invested)).font(.subheadline.weight(.semibold).monospacedDigit())
                if h.isStablecoin { Text("Estable · 0%").font(.caption.weight(.semibold)).foregroundStyle(VexiaColor.textSecondary) }
                else if let g = h.gain, let p = h.gainPercent { gainLabel(g, p) }
                else { Text("Sin precio").font(.caption).foregroundStyle(VexiaColor.textSecondary) }
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private func gainLabel(_ gain: Double, _ percent: Double) -> some View {
        let zero = abs(percent) < 0.05
        return Text(zero ? "0%" : "\(gain >= 0 ? "▲ +" : "▼ ")\(Fmt.grouped(abs(percent), decimals: 1))%")
            .font(.caption.weight(.semibold))
            .foregroundStyle(zero ? VexiaColor.textSecondary : (gain >= 0 ? VexiaColor.incomeText : VexiaColor.expenseText))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.title).foregroundStyle(VexiaColor.brandBlue)
                .frame(width: 64, height: 64).background(VexiaColor.tintSoft, in: .rect(cornerRadius: 20))
            Text("Empieza tu portafolio").font(.title3.weight(.bold))
            Text(vm.segment == .stocks ? String(localized: "Registra tu primera compra de acciones y Vexia calculará tu ganancia, el precio promedio y las ventas.")
                     : String(localized: "Registra tu primera compra de cripto y Vexia calculará tu ganancia, el precio promedio y las ventas."))
                .font(.subheadline).foregroundStyle(VexiaColor.textSecondary).multilineTextAlignment(.center)
            Button("Registrar primera compra") { formRequest = FormRequest() }
                .buttonStyle(.glassProminent).controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.background, in: .rect(cornerRadius: 22))
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 0, content: c)
            .padding(.horizontal, 14)
            .background(.background, in: .rect(cornerRadius: 20))
    }

    private func emptyRow(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.subheadline).foregroundStyle(VexiaColor.textSecondary).frame(maxWidth: .infinity).padding(.vertical, 18)
    }

    private func openEdit(id: Int) {
        guard let target = vm.operation(id: id) else { return }
        switch target {
        case .stock(let s): formRequest = FormRequest(editingStock: s)
        case .crypto(let c): formRequest = FormRequest(editingCrypto: c)
        }
    }

    private func deleteOp(id: Int) {
        Task { await vm.deleteOperation(id: id) }
    }

    static let placeholder = HoldingRow(symbol: "XXXX", quantity: 10, avgPrice: 100, invested: 1000, value: 1100, sector: nil,
                                        isStablecoin: false, exchanges: [], operationCount: 1)
}
