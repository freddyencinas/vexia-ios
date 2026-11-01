import SwiftUI
import Charts

struct DashboardView: View {
    @State var vm: DashboardViewModel
    let container: AppContainer
    var openAssistant: (String?) -> Void
    var openBudgets: () -> Void
    @Environment(SessionViewModel.self) private var session

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                BalanceHeroCard(vm: vm) { Task { await vm.load(force: true) } }
                if let insight = vm.insight { insightCard(insight) }
                if let m = vm.month { MonthSummaryCard(month: m, mask: vm.masked) }
                if !vm.accounts.isEmpty { AccountsStrip(accounts: vm.accounts, mask: vm.masked) }
                if !vm.rateCodes.isEmpty {
                    NavigationLink {
                        RatesView(vm: RatesViewModel(catalog: container.catalog))
                    } label: { RatesSummaryRow(codes: vm.rateCodes, quotes: vm.rates) }
                    .buttonStyle(.plain)
                }
                if !vm.recent.isEmpty { recentCard }
                if let cf = vm.data.cashFlow, !cf.points.isEmpty { CashFlowCard(cashFlow: cf, currency: vm.currency) }
                if let sp = vm.data.spending, !sp.categories.isEmpty { SpendingCard(spending: sp, currency: vm.currency) }
                if let p = vm.data.performance, p.combinedValue > 0 { PerformanceCard(perf: p, currency: vm.currency) }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(greeting)
        .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es"))).capitalizedFirst)
        .refreshable { await vm.load(force: true) }
        .task { await vm.load() }
    }

    private var greeting: String { session.user.map { "Hola, \($0.firstName)" } ?? "Hola" }

    private func insightCard(_ i: DashboardViewModel.Insight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles").foregroundStyle(VexiaColor.violet)
                .frame(width: 36, height: 36).background(VexiaColor.violetSoft, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(i.title).font(.subheadline.weight(.semibold))
                Text(i.body).font(.footnote).foregroundStyle(VexiaColor.textSecondary)
                Button("Crear presupuesto ›") { openAssistant("Ayúdame a crear un presupuesto mensual con mis gastos") }
                    .font(.subheadline.weight(.semibold)).padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recientes").font(.headline).padding(.vertical, 10)
            ForEach(vm.recent) { tx in
                Divider()
                TransactionRow(tx: tx).padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 4)
        .background(.background, in: .rect(cornerRadius: 20))
    }
}

/// Hero balance. Shows live / derived / cached (with time + retry) / unavailable — never a fake 0.
struct BalanceHeroCard: View {
    let vm: DashboardViewModel
    var retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Balance total").font(.subheadline.weight(.medium)).foregroundStyle(Color(hex: 0xD6DEF5))
                Spacer()
                Button { withAnimation { vm.hideBalances.toggle() } } label: {
                    Image(systemName: vm.hideBalances ? "eye.slash" : "eye").frame(width: 28, height: 22)
                }
                .buttonStyle(.glass).tint(.white)
                .accessibilityLabel(vm.hideBalances ? "Mostrar saldos" : "Ocultar saldos")
            }
            switch vm.balance {
            case .loading:
                Text("$00.000,00").font(.system(size: 38, weight: .bold, design: .rounded)).redacted(reason: .placeholder)
            case .unavailable:
                Text("—").font(.system(size: 38, weight: .bold, design: .rounded))
                status("No pudimos cargar tu balance")
            case .live(let v, let c):
                amount(v, c)
                if let o = vm.data.overview, o.balanceChange != 0 {
                    Text("\(o.balanceChange >= 0 ? "▲" : "▼") \(vm.masked(Fmt.money(abs(o.balanceChange), currency: c))) este mes")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Color(hex: 0x9FE6C8))
                }
            case .derived(let v, let c):
                amount(v, c)
                Text("Suma de tus cuentas · resumen no disponible").font(.footnote).foregroundStyle(Color(hex: 0xD6DEF5))
            case .cached(let v, let c, let at):
                amount(v, c)
                status("Sin conexión · dato de las \(Fmt.time(at))")
            }
            if let o = vm.data.overview {
                HStack(spacing: 8) {
                    split("Efectivo", o.cashBalance)
                    split("Inversiones", o.investmentsBalance)
                    split("Cripto", o.cryptoBalance)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(VexiaColor.brandFill, in: .rect(cornerRadius: 24))
    }

    private func amount(_ v: Double, _ c: String) -> some View {
        Text(vm.masked(Fmt.money(v, currency: c)))
            .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
            .contentTransition(.numericText()).minimumScaleFactor(0.5).lineLimit(1)
    }

    private func status(_ text: String) -> some View {
        HStack {
            Text(text).font(.footnote)
            Spacer()
            Button("Reintentar", action: retry).font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).frame(minHeight: 32)
                .background(.white, in: .capsule).foregroundStyle(Color(hex: 0x15307C))
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 4)
        .background(.white.opacity(0.14), in: .rect(cornerRadius: 14))
    }

    private func split(_ title: LocalizedStringKey, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Color(hex: 0xD6DEF5))
            Text(vm.masked(Fmt.money(v, currency: vm.currency, compact: true))).font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}

struct MonthSummaryCard: View {
    let month: DashboardViewModel.MonthTotals
    let mask: (String) -> String
    var body: some View {
        let maxV = max(month.income, month.expenses, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(month.label).font(.headline)
                Spacer()
                let net = Text(mask((month.net >= 0 ? "+" : "") + Fmt.money(month.net, currency: month.currency)))
                    .font(.footnote.weight(.bold)).foregroundStyle(month.net >= 0 ? VexiaColor.incomeText : VexiaColor.expenseText)
                Text("\(Text("Neto ").font(.footnote).foregroundStyle(VexiaColor.textSecondary))\(net)")
            }
            bar("Ingresos", month.income, maxV, VexiaColor.brandGreen, VexiaColor.greenSoft)
            bar("Gastos", month.expenses, maxV, VexiaColor.expenseFill, VexiaColor.redSoft)
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func bar(_ t: String, _ v: Double, _ maxV: Double, _ fill: Color, _ track: Color) -> some View {
        VStack(spacing: 4) {
            HStack { Text(t).foregroundStyle(VexiaColor.textSecondary); Spacer(); Text(mask(Fmt.money(v, currency: month.currency))).fontWeight(.semibold).monospacedDigit() }
                .font(.footnote)
            GeometryReader { g in
                Capsule().fill(track).overlay(alignment: .leading) { Capsule().fill(fill).frame(width: BarMetrics.width(g.size.width, v / maxV)) }
            }
            .frame(height: 8)
        }
    }
}

/// Compact "Tasas del día" entry on Inicio → RatesView.
struct RatesSummaryRow: View {
    let codes: [String]
    let quotes: [String: RateQuote]
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dollarsign.arrow.circlepath").foregroundStyle(VexiaColor.brandGreen)
                .frame(width: 36, height: 36).background(VexiaColor.greenSoft, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Tasas del día").font(.subheadline.weight(.semibold))
                Text(codes.prefix(3).map { c in "\(c) \(quotes[c].map { Fmt.grouped($0.rate) } ?? "—")" }.joined(separator: " · "))
                    .font(.footnote.monospacedDigit()).foregroundStyle(VexiaColor.textSecondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 20))
        .contentShape(.rect)
    }
}

struct AccountsStrip: View {
    let accounts: [Account]
    let mask: (String) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Cuentas", systemImage: "wallet.bifold")
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(accounts) { a in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                IconBadge(symbol: a.type.symbol, color: Color(hexString: a.color) ?? VexiaColor.brandBlue, size: 32)
                                if a.isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                            }
                            Text(a.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(mask(Fmt.money(a.balance, currency: a.code))).font(.headline.monospacedDigit())
                                .foregroundStyle(a.balance < 0 ? VexiaColor.error : .primary)
                        }
                        .padding(14).frame(width: 170, alignment: .leading)
                        .background(.background.secondary, in: .rect(cornerRadius: 20))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct CashFlowCard: View {
    let cashFlow: CashFlow
    let currency: String
    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Flujo de caja · 6 meses", systemImage: "chart.bar")
                Chart {
                    ForEach(cashFlow.points) { p in
                        BarMark(x: .value("Mes", p.date, unit: .month), y: .value("Monto", p.income))
                            .foregroundStyle(by: .value("Tipo", "Ingresos")).position(by: .value("Tipo", "Ingresos"))
                        BarMark(x: .value("Mes", p.date, unit: .month), y: .value("Monto", p.expenses))
                            .foregroundStyle(by: .value("Tipo", "Gastos")).position(by: .value("Tipo", "Gastos"))
                    }
                    ForEach(cashFlow.points) { p in
                        LineMark(x: .value("Mes", p.date, unit: .month), y: .value("Neto", p.netFlow))
                            .foregroundStyle(VexiaColor.brandBlue).interpolationMethod(.catmullRom)
                            .symbol(.circle)
                    }
                }
                .chartForegroundStyleScale(["Ingresos": VexiaColor.income, "Gastos": VexiaColor.error])
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .frame(height: 200)
                HStack {
                    StatTile(title: "Neto", value: Fmt.money(cashFlow.netFlow, currency: currency, compact: true),
                             symbol: "equal.circle", tint: cashFlow.netFlow >= 0 ? VexiaColor.success : VexiaColor.error)
                }
            }
        }
    }
}

struct SpendingCard: View {
    let spending: SpendingAnalysis
    let currency: String
    @State private var selected: Double?

    private var top: [SpendingAnalysis.Category] { Array(spending.categories.sorted { $0.amount > $1.amount }.prefix(6)) }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Gastos del mes", systemImage: "chart.pie")
                HStack(alignment: .center, spacing: 16) {
                    Chart(top) { c in
                        SectorMark(angle: .value("Monto", c.amount), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .cornerRadius(4)
                            .foregroundStyle(by: .value("Categoría", c.categoryName))
                    }
                    .chartLegend(.hidden)
                    .chartForegroundStyleScale(domain: top.map(\.categoryName), range: VexiaColor.categoryPalette)
                    .frame(width: 140, height: 140)
                    .overlay {
                        VStack(spacing: 2) {
                            Text("Total").font(.caption2).foregroundStyle(.secondary)
                            Text(Fmt.money(spending.totalSpent, currency: currency, compact: true)).font(.subheadline.bold().monospacedDigit())
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(top.enumerated()), id: \.element.id) { i, c in
                            HStack(spacing: 6) {
                                Circle().fill(VexiaColor.categoryPalette[i % VexiaColor.categoryPalette.count]).frame(width: 8, height: 8)
                                Text(c.categoryName).font(.caption).lineLimit(1)
                                Spacer()
                                Text(Fmt.percent(c.percentage)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if spending.changePercent != 0 {
                    Label("\(spending.changePercent > 0 ? "+" : "")\(Fmt.percent(spending.changePercent)) vs. periodo anterior",
                          systemImage: spending.changePercent > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption).foregroundStyle(spending.changePercent > 0 ? VexiaColor.error : VexiaColor.success)
                }
                if !spending.topExpenses.isEmpty {
                    Divider()
                    Text("Mayores gastos").font(.subheadline.weight(.semibold))
                    ForEach(Array(spending.topExpenses.prefix(3).enumerated()), id: \.element.id) { i, e in
                        HStack {
                            Text("\(i + 1)").font(.caption.bold()).frame(width: 22, height: 22)
                                .background(.quaternary, in: .circle)
                            VStack(alignment: .leading) {
                                Text(e.description).font(.subheadline).lineLimit(1)
                                Text(e.categoryName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Fmt.money(e.amount, currency: currency)).font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }
    }
}

struct PerformanceCard: View {
    let perf: PortfolioPerformance
    let currency: String
    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Rendimiento del portafolio", systemImage: "chart.line.uptrend.xyaxis")
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.money(perf.combinedValue, currency: currency)).font(.title2.bold().monospacedDigit())
                    Spacer()
                    GainText(value: perf.combinedGain, percent: perf.combinedGainPercent, currency: currency)
                }
                HStack(spacing: 10) {
                    bucket("Acciones", perf.investments, "building.2")
                    bucket("Cripto", perf.crypto, "bitcoinsign.circle")
                }
            }
        }
    }
    private func bucket(_ t: LocalizedStringKey, _ b: PortfolioPerformance.Bucket, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(t, systemImage: s).font(.caption).foregroundStyle(.secondary)
            Text(Fmt.money(b.totalValue, currency: currency, compact: true)).font(.headline.monospacedDigit())
            GainText(value: b.totalGain, percent: b.totalGainPercent, currency: currency)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
    }
}

