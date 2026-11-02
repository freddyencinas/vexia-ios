import SwiftUI
import Charts

/// Inversiones (design: market selector in the title, neutral zero, view chips, exchange filter, rich empty state).
struct InvestmentsView: View {
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
                Button("Actualizar precios", systemImage: "arrow.triangle.2.circlepath") { Task { await vm.updatePrices() } }
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
                let ops = vm.segment == .stocks
                    ? vm.stockOps.map { (id: $0.id, sym: $0.symbol, type: $0.operationType, qty: $0.quantity, price: $0.buyPrice, date: $0.date, fee: $0.fee) }
                    : vm.filteredCryptoOps.map { (id: $0.id, sym: $0.cryptoSymbol, type: $0.transactionType, qty: $0.quantity, price: $0.pricePerUnit, date: $0.date, fee: $0.fee) }
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
        let realized = list.reduce(0) { $0 + $1.realized }
        let unrealized = list.reduce(0) { $0 + $1.unrealized }
        let maxAbs = max(list.map { abs($0.pnlPercent) }.max() ?? 1, 1)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                statTile("No realizado", unrealized)
                statTile("Realizado (ventas)", realized)
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
                    ForEach(h.exchanges.prefix(2), id: \.self) { e in
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
        if vm.segment == .stocks, let s = vm.stockOps.first(where: { $0.id == id }) { formRequest = FormRequest(editingStock: s) }
        if vm.segment == .crypto, let c = vm.cryptoOps.first(where: { $0.id == id }) { formRequest = FormRequest(editingCrypto: c) }
    }

    private func deleteOp(id: Int) {
        Task {
            if vm.segment == .stocks, let s = vm.stockOps.first(where: { $0.id == id }) { await vm.deleteStock(s) }
            if vm.segment == .crypto, let c = vm.cryptoOps.first(where: { $0.id == id }) { await vm.deleteCrypto(c) }
        }
    }

    static let placeholder = HoldingRow(symbol: "XXXX", quantity: 10, avgPrice: 100, invested: 1000, value: 1100, sector: nil,
                                        isStablecoin: false, exchanges: [], operationCount: 1)
}

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
                        Text([holding.sector, holding.exchanges.first].compactMap { $0?.nilIfEmpty }.joined(separator: " · ").nilIfEmpty ?? (vm.segment == .stocks ? String(localized: "Acción") : String(localized: "Cripto")))
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

/// Comprar o vender (design): stepper, today's price, fee, account, estimated profit / new average, max validation.
struct InvestmentFormView: View {
    @State var vm: InvestmentFormViewModel
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Operación", selection: $vm.draft.operationType) {
                        Text("Comprar").tag(OperationType.buy)
                        Text("Vender").tag(OperationType.sell)
                    }
                    .pickerStyle(.segmented).disabled(vm.editingId != nil)
                    .listRowBackground(Color.clear).listRowInsets(.init())
                }
                Section {
                    if vm.holding == nil && vm.editingId == nil {
                        TextField(vm.isCrypto ? String(localized: "Símbolo (BTC, ETH…)") : String(localized: "Símbolo (AAPL, MSFT…)"), text: $vm.draft.symbol).focused($typing)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    } else {
                        LabeledContent(vm.isCrypto ? String(localized: "Cripto") : String(localized: "Acción")) {
                            let owned = vm.holding.map { String(localized: "  · tienes \(Fmt.quantity($0.quantity, crypto: vm.isCrypto))") } ?? ""
                            Text("\(Text(vm.draft.symbol.uppercased()).fontWeight(.semibold))\(Text(owned).foregroundStyle(VexiaColor.textSecondary))")
                        }
                    }
                    if vm.isCrypto {
                        TextField("Exchange (Binance, Airtm…)", text: $vm.draft.exchangePlatform).focused($typing)
                        Toggle("Stablecoin", isOn: $vm.draft.isStablecoin)
                    } else if vm.holding == nil {
                        TextField("Sector (opcional)", text: $vm.draft.sector).focused($typing)
                    }
                }
                Section {
                    HStack {
                        Text("Cantidad")
                        Spacer()
                        Button { vm.step(-1) } label: { Image(systemName: "minus").frame(width: 32, height: 32) }
                            .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Menos")
                        TextField("0", text: $vm.quantityText).focused($typing).keyboardType(.decimalPad).multilineTextAlignment(.center)
                            .font(.title3.weight(.bold).monospacedDigit()).frame(width: 90)
                        Button { vm.step(1) } label: { Image(systemName: "plus").frame(width: 32, height: 32) }
                            .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Más")
                    }
                    if vm.overMax, let m = vm.maxSell {
                        Text("Solo tienes \(Fmt.quantity(m, crypto: vm.isCrypto)) para vender.").font(.footnote.weight(.semibold)).foregroundStyle(VexiaColor.expenseText)
                    }
                    LabeledContent(vm.isSell ? String(localized: "Precio de venta") : String(localized: "Precio por unidad")) {
                        TextField("0,00", text: $vm.priceText).focused($typing).keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                    }
                    LabeledContent("Comisión") {
                        TextField("0,00", text: $vm.feeText).focused($typing).keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                    }
                    if !vm.accounts.isEmpty && vm.editingId == nil {
                        Picker(vm.isSell ? String(localized: "Recibir en") : String(localized: "Pagar con"), selection: $vm.draft.accountId) {
                            ForEach(vm.accounts) { Text("\($0.name) · \(Fmt.money($0.balance, currency: $0.code))").tag(Optional($0.id)) }
                        }
                    }
                    DatePicker("Fecha", selection: $vm.draft.date, displayedComponents: .date)
                }
                Section {
                    LabeledContent(vm.isSell ? String(localized: "Recibirás") : String(localized: "Pagarás")) { Text(Fmt.money(vm.total)).fontWeight(.bold).monospacedDigit() }
                    if let p = vm.estimatedProfit {
                        LabeledContent("Ganancia estimada") {
                            Text((p >= 0 ? "+" : "−") + Fmt.money(abs(p))).fontWeight(.bold)
                                .foregroundStyle(p >= 0 ? VexiaColor.incomeText : VexiaColor.expenseText)
                        }
                    }
                } footer: {
                    if let h = vm.holding, vm.isSell { Text("Calculado con tu precio promedio de \(Fmt.money(h.avgPrice)).") }
                    else if let avg = vm.newAverage { Text("Tu nuevo precio promedio será \(Fmt.money(avg)).") }
                }
                Section { TextField("Notas (opcional)", text: $vm.draft.notes, axis: .vertical).focused($typing) }
            }
            .navigationTitle(vm.editingId != nil ? String(localized: "Editar operación") : (vm.isSell ? String(localized: "Vender") : String(localized: "Comprar")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { typing = false } } }
            .safeAreaInset(edge: .bottom) {
                if !typing {
                Button {
                    Task { if await vm.submit() { onSaved(); dismiss() } }
                } label: { Text(vm.ctaTitle).font(.headline).frame(maxWidth: .infinity, minHeight: 34) }
                .buttonStyle(.glassProminent).controlSize(.large)
                .tint(vm.isSell ? VexiaColor.expenseText : VexiaColor.brandBlue)
                .disabled(!vm.canSubmit)
                .padding(.horizontal).padding(.bottom, 8)
                }
            }
            .task { await vm.loadAccounts() }
            .errorAlert($vm.errorMessage)
        }
    }
}
