import SwiftUI

/// "Tasas del día": how much 1 USD is worth in each of the user's currencies, with source,
/// deviation vs. external provider, buy/sell when available, and actions.
@Observable
final class RatesViewModel {
    struct Row: Identifiable, Equatable {
        var id: String { code }
        let code: String
        var quote: RateQuote?
        var external: Double?
        var buy: Double?
        var sell: Double?
        var deviation: Double? {
            guard let q = quote, q.source != .external, let e = external, e > 0 else { return nil }
            return (q.rate - e) / e * 100
        }
    }

    private(set) var rows: [Row] = []
    private(set) var updatedAt: Date?
    private(set) var isLoading = false
    var editing: String?
    var message: String?
    let catalog: CatalogRepository
    private let loadRates: LoadTransactionRatesUseCase

    init(catalog: CatalogRepository) { self.catalog = catalog; loadRates = LoadTransactionRatesUseCase(catalog: catalog) }

    func load(forceExternal: Bool = false) async {
        isLoading = true; defer { isLoading = false }
        let codes = await loadRates.currencies()
        async let q = loadRates(codes, forceExternal: forceExternal)
        async let ext = loadRates(codes, forceExternal: true)
        async let country = try? catalog.countryRates()
        let quotes = await q, externals = await ext
        let cr = Dictionary((await country ?? []).map { ($0.currencyCode.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
        rows = codes.map { c in
            let r = cr[c]
            return Row(code: c, quote: quotes[c], external: externals[c]?.rate,
                       buy: (r?.buyRate ?? 0) > 0 ? r?.buyRate : nil, sell: (r?.sellRate ?? 0) > 0 ? r?.sellRate : nil)
        }
        updatedAt = .now
    }

    func save(_ code: String, _ v: Double) async {
        do {
            try await catalog.saveUSDRate(code: code, rate: v, date: .now)
            message = "Tasa \(code) guardada: \(Fmt.grouped(v))"
            await load()
        } catch { message = error.localizedDescription }
    }

    static func name(_ code: String) -> String {
        ["BOB": "Boliviano", "VES": "Bolívar", "EUR": "Euro", "ARS": "Peso argentino", "CLP": "Peso chileno",
         "COP": "Peso colombiano", "MXN": "Peso mexicano", "PEN": "Sol peruano", "BRL": "Real brasileño", "GBP": "Libra esterlina"][code]
            ?? Locale(identifier: "es").localizedString(forCurrencyCode: code)?.capitalized ?? code
    }

    static func sourceText(_ q: RateQuote?) -> String {
        switch q?.source {
        case .database, .saved: "Guardada por ti"
        case .external: "Fuente externa"
        case .manual: "Manual"
        case .snapshot: "Registrada en el movimiento"
        case nil: "Sin tasa"
        }
    }
}

struct RatesView: View {
    @State var vm: RatesViewModel
    @Environment(\.container) private var container
    @State private var exchangeDraft: TransactionDraft?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Cuánto vale 1 dólar en tus monedas" + (vm.updatedAt.map { " · actualizado \(Fmt.time($0))" } ?? ""))
                    .font(.footnote).foregroundStyle(VexiaColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if vm.rows.isEmpty && vm.isLoading {
                    ForEach(0..<3, id: \.self) { _ in row(.init(code: "XXX")).redacted(reason: .placeholder) }
                }
                ForEach(vm.rows) { r in row(r) }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Tasas del día")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await vm.load(forceExternal: true) } } label: {
                    if vm.isLoading { ProgressView() } else { Label("Actualizar", systemImage: "arrow.clockwise") }
                }
            }
        }
        .refreshable { await vm.load(forceExternal: true) }
        .task { if vm.rows.isEmpty { await vm.load() } }
        .sheet(item: Binding(get: { vm.editing.map(IdentifiedCode.init) }, set: { vm.editing = $0?.id })) { item in
            RateEditorSheet(vm: RateEditorViewModel(code: item.id, current: vm.rows.first { $0.code == item.id }?.quote?.rate,
                                                    previewAmount: nil, catalog: vm.catalog),
                            onApplyOnce: nil, onSaveGlobal: { v in await vm.save(item.id, v) })
        }
        .sheet(item: Binding(get: { exchangeDraft.map(IdentifiedDraft.init) }, set: { exchangeDraft = $0?.draft })) { item in
            if let container {
                TransactionFormView(vm: TransactionFormViewModel(save: container.saveTransaction, catalog: container.catalog, prefill: item.draft)) {}
            }
        }
        .alert(vm.message ?? "", isPresented: Binding(get: { vm.message != nil }, set: { if !$0 { vm.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func row(_ r: RatesViewModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(Fmt.symbol(r.code) ?? r.code).font(.subheadline.weight(.bold)).foregroundStyle(VexiaColor.brandBlue)
                    .frame(width: 44, height: 44).background(VexiaColor.tintSoft, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(RatesViewModel.name(r.code)).font(.body.weight(.semibold))
                    Text(RatesViewModel.sourceText(r.quote)).font(.caption).foregroundStyle(VexiaColor.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(r.quote.map { Fmt.grouped($0.rate) } ?? "—").font(.title3.weight(.bold).monospacedDigit())
                    if let d = r.deviation, abs(d) >= 0.05 {
                        Text("\(d > 0 ? "+" : "−")\(Fmt.grouped(abs(d), decimals: 1))% vs. externa")
                            .font(.caption.weight(.semibold)).foregroundStyle(abs(d) > 10 ? VexiaColor.cautionText : VexiaColor.textSecondary)
                    }
                }
            }
            if let b = r.buy, let s = r.sell {
                HStack(spacing: 8) { pill("Compra", b); pill("Venta", s) }
            }
            HStack(spacing: 8) {
                Button { vm.editing = r.code } label: { Text("Fijar mi tasa").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
                Button { exchangeDraft = exchangeDraftFor(r.code) } label: { Text("Cambiar").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    private func pill(_ t: String, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.caption2).foregroundStyle(VexiaColor.textSecondary)
            Text(Fmt.grouped(v)).font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private func exchangeDraftFor(_ code: String) -> TransactionDraft {
        var d = TransactionDraft(); d.type = .transfer; d.toCurrencyCode = code; return d
    }
}

struct IdentifiedCode: Identifiable { let id: String }
struct IdentifiedDraft: Identifiable { let id = UUID(); let draft: TransactionDraft }
