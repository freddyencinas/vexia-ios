import SwiftUI

/// Unified holding row for stocks and crypto (design: one list style for both markets).
struct HoldingRow: Identifiable, Hashable {
    var id: String { symbol }
    let symbol: String
    let quantity: Double
    let avgPrice: Double
    let invested: Double
    let value: Double?          // nil when the backend has no current price
    let sector: String?
    let isStablecoin: Bool
    let exchanges: [String]
    let operationCount: Int

    var gain: Double? { value.map { $0 - invested } }
    var gainPercent: Double? { guard let g = gain, invested > 0 else { return nil }; return g / invested * 100 }
}

@Observable
final class InvestmentsViewModel {
    enum Segment: String, CaseIterable, Identifiable { case stocks, crypto; var id: String { rawValue }
        var title: String { self == .stocks ? String(localized: "Acciones") : String(localized: "Cripto") } }
    enum Tab: String, CaseIterable, Identifiable { case portfolio, pnl, sales, operations; var id: String { rawValue }
        var title: String { switch self { case .portfolio: String(localized: "Portafolio"); case .pnl: String(localized: "P&L"); case .sales: String(localized: "Ventas"); case .operations: String(localized: "Operaciones") } } }

    var segment: Segment = .stocks
    var tab: Tab = .portfolio
    var exchange: String? = nil
    private(set) var isLoading = false
    private(set) var loadedOnce = false
    var errorMessage: String?

    private(set) var positions: [StockPosition] = []
    private(set) var pnlSummary: PnLSummary?
    private(set) var stockOps: [Investment] = []
    private(set) var cryptoPortfolio: CryptoPortfolio?
    private(set) var cryptoPositions: [CryptoPosition] = []
    private(set) var cryptoOps: [CryptoTransaction] = []
    private(set) var pnl: [AssetPnL] = []
    private(set) var sales: [SaleRecord] = []

    let stocksRepo: InvestmentsRepository
    let cryptoRepo: CryptoRepository

    private let catalog: CatalogRepository?
    /// Exchange category id → name (crypto operations store the id).
    private(set) var exchangeNames: [String: String] = [:]

    init(stocks: InvestmentsRepository, crypto: CryptoRepository, catalog: CatalogRepository? = nil) {
        stocksRepo = stocks; cryptoRepo = crypto; self.catalog = catalog
    }

    func load() async {
        isLoading = true; defer { isLoading = false; loadedOnce = true }
        switch segment {
        case .stocks:
            async let p = try? stocksRepo.positions()
            async let s = try? stocksRepo.pnlSummary()
            async let l = try? stocksRepo.pnl()
            async let sa = try? stocksRepo.sales()
            async let o = try? stocksRepo.operations(page: 1)
            positions = await p ?? []; pnlSummary = await s; pnl = await l ?? []
            sales = await sa ?? []; stockOps = await o?.items ?? []
        case .crypto:
            async let pf = try? cryptoRepo.portfolio()
            async let p = try? cryptoRepo.positions()
            async let l = try? cryptoRepo.pnl()
            async let sa = try? cryptoRepo.sales()
            async let o = try? cryptoRepo.transactions(page: 1)
            if exchangeNames.isEmpty, let cats = try? await catalog?.categories(type: "exchange") {
                exchangeNames = Dictionary(cats.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            }
            cryptoPortfolio = await pf; cryptoPositions = await p ?? []; pnl = await l ?? []
            sales = await sa ?? []; cryptoOps = await o?.items ?? []
        }
    }

    func updatePrices() async {
        do {
            if segment == .stocks { try await stocksRepo.updatePrices() } else { try await cryptoRepo.updatePrices() }
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteStock(_ inv: Investment) async {
        do { try await stocksRepo.delete(id: inv.id); await load() } catch { errorMessage = error.localizedDescription }
    }
    func deleteCrypto(_ tx: CryptoTransaction) async {
        do { try await cryptoRepo.delete(id: tx.id); await load() } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Derived

    var exchanges: [String] {
        // Values are exchange category ids (or legacy names); unresolved ids are never shown.
        Array(Set((cryptoOps.compactMap { $0.exchangePlatform?.nilIfEmpty } + pnl.compactMap { $0.exchange?.nilIfEmpty })
            .filter { exchangeLabel($0) != nil }))
            .sorted { (exchangeLabel($0) ?? $0).localizedStandardCompare(exchangeLabel($1) ?? $1) == .orderedAscending }
    }

    /// Display name for a stored exchange value; nil for an id we can't resolve.
    func exchangeLabel(_ raw: String) -> String? {
        exchangeNames[raw] ?? (UUID(uuidString: raw) == nil ? raw : nil)
    }
    func exchangeLabels(_ raws: [String]) -> [String] { raws.compactMap(exchangeLabel) }

    var holdings: [HoldingRow] {
        switch segment {
        case .stocks:
            return positions.filter { $0.netQuantity > 1e-6 }.map {
                HoldingRow(symbol: $0.symbol, quantity: $0.netQuantity, avgPrice: $0.avgBuyPrice, invested: $0.totalInvested,
                           value: $0.currentValue, sector: $0.sector, isStablecoin: false, exchanges: [], operationCount: $0.operationCount)
            }
        case .crypto:
            let pnlBySymbol = Dictionary(grouping: pnl, by: { $0.symbol })
            return cryptoPositions.filter { $0.netQuantity > 1e-8 }.compactMap { p in
                let ex = Array(Set(cryptoOps.filter { $0.cryptoSymbol == p.cryptoSymbol }.compactMap { $0.exchangePlatform?.nilIfEmpty })).sorted()
                if let exchange, !ex.contains(exchange) { return nil }
                let value = pnlBySymbol[p.cryptoSymbol].map { $0.reduce(0) { $0 + $1.currentValue } }.flatMap { $0 > 0 ? $0 : nil }
                    ?? (p.isStablecoin ? p.netQuantity : nil)
                return HoldingRow(symbol: p.cryptoSymbol, quantity: p.netQuantity, avgPrice: p.avgBuyPrice, invested: p.totalInvested,
                                  value: value, sector: nil, isStablecoin: p.isStablecoin, exchanges: ex, operationCount: p.operationCount)
            }
        }
    }

    var filteredPnL: [AssetPnL] { exchange.map { e in pnl.filter { $0.exchange == e } } ?? pnl }
    var filteredCryptoOps: [CryptoTransaction] { exchange.map { e in cryptoOps.filter { $0.exchangePlatform == e } } ?? cryptoOps }

    var headline: (value: Double, invested: Double, gain: Double, percent: Double) {
        let h = holdings
        let invested = h.reduce(0) { $0 + $1.invested }
        let value = h.reduce(0) { $0 + ($1.value ?? $1.invested) }
        if exchange == nil, segment == .stocks, let s = pnlSummary, s.currentValue > 0 {
            return (s.currentValue, s.totalInvested, s.totalPnL, s.totalPnLPercent)
        }
        if exchange == nil, segment == .crypto, let c = cryptoPortfolio, c.currentValue > 0 {
            return (c.currentValue, c.totalInvested, c.gainLoss, c.gainLossPercent)
        }
        let gain = value - invested
        return (value, invested, gain, invested > 0 ? gain / invested * 100 : 0)
    }

    /// Stocks: share by sector. Crypto: volatile vs stablecoins.
    var allocation: [(label: String, share: Double)] {
        let h = holdings
        let total = h.reduce(0) { $0 + ($1.value ?? $1.invested) }
        guard total > 0 else { return [] }
        switch segment {
        case .stocks:
            let groups = Dictionary(grouping: h, by: { $0.sector?.nilIfEmpty.map(SectorNames.label) ?? String(localized: "Otros") })
            return groups.map { ($0.key, $0.value.reduce(0) { $0 + ($1.value ?? $1.invested) } / total) }.sorted { $0.1 > $1.1 }
        case .crypto:
            let stable = h.filter(\.isStablecoin).reduce(0) { $0 + ($1.value ?? $1.invested) }
            return [(String(localized: "Volátil"), (total - stable) / total), (String(localized: "Stablecoins"), stable / total)].filter { $0.1 > 0 }
        }
    }

    var pnlRealizedTotal: Double { filteredPnL.reduce(0) { $0 + $1.realized } }
    var pnlUnrealizedTotal: Double { filteredPnL.reduce(0) { $0 + $1.unrealized } }
    /// Floor of 1 keeps bar ratios finite when every asset is flat.
    var pnlMaxAbsPercent: Double { max(filteredPnL.map { abs($0.pnlPercent) }.max() ?? 1, 1) }

    typealias OperationRow = (id: Int, sym: String, type: OperationType, qty: Double, price: Double, date: Date, fee: Double)

    var operationRows: [OperationRow] {
        segment == .stocks
            ? stockOps.map { (id: $0.id, sym: $0.symbol, type: $0.operationType, qty: $0.quantity, price: $0.buyPrice, date: $0.date, fee: $0.fee) }
            : filteredCryptoOps.map { (id: $0.id, sym: $0.cryptoSymbol, type: $0.transactionType, qty: $0.quantity, price: $0.pricePerUnit, date: $0.date, fee: $0.fee) }
    }

    enum OperationTarget { case stock(Investment), crypto(CryptoTransaction) }

    func operation(id: Int) -> OperationTarget? {
        switch segment {
        case .stocks: stockOps.first { $0.id == id }.map(OperationTarget.stock)
        case .crypto: cryptoOps.first { $0.id == id }.map(OperationTarget.crypto)
        }
    }

    func deleteOperation(id: Int) async {
        switch operation(id: id) {
        case .stock(let s): await deleteStock(s)
        case .crypto(let c): await deleteCrypto(c)
        case nil: break
        }
    }

    func operations(for symbol: String) -> [(id: Int, type: OperationType, qty: Double, price: Double, date: Date, exchange: String?)] {
        switch segment {
        case .stocks: stockOps.filter { $0.symbol == symbol }.map { ($0.id, $0.operationType, $0.quantity, $0.buyPrice, $0.date, nil) }
        case .crypto: cryptoOps.filter { $0.cryptoSymbol == symbol }.map { ($0.id, $0.transactionType, $0.quantity, $0.pricePerUnit, $0.date, $0.exchangePlatform) }
        }
    }
}

/// Buy/sell form (design: "Comprar o vender"). Knows the current holding to validate sells,
/// estimate realized profit (avg cost) and the new average after a buy.
@Observable
final class InvestmentFormViewModel {
    var draft: InvestmentDraft
    /// Fractions allowed up to what the backend accepts (shares 6, crypto 8 decimals).
    var quantityText = "" { didSet { let t = AmountMath.sanitize(quantityText, maxDecimals: maxDecimals); if t != quantityText { quantityText = t } } }
    var priceText = ""
    var feeText = ""
    let isCrypto: Bool
    let editingId: Int?
    let holding: HoldingRow?
    private(set) var isSaving = false
    private(set) var accounts: [Account] = []
    var errorMessage: String?
    private let stocks: InvestmentsRepository
    private let crypto: CryptoRepository
    private let catalog: CatalogRepository?

    init(isCrypto: Bool, stocks: InvestmentsRepository, crypto: CryptoRepository, catalog: CatalogRepository? = nil,
         holding: HoldingRow? = nil, operation: OperationType = .buy,
         editingStock: Investment? = nil, editingCrypto: CryptoTransaction? = nil) {
        self.isCrypto = isCrypto; self.stocks = stocks; self.crypto = crypto; self.catalog = catalog; self.holding = holding
        var d = InvestmentDraft()
        d.operationType = operation
        if let h = holding {
            d.symbol = h.symbol; d.isStablecoin = h.isStablecoin
            if let v = h.value, h.quantity > 0 { d.price = (v / h.quantity * 100).rounded() / 100 }
            d.exchangePlatform = h.exchanges.first ?? ""
        }
        if let s = editingStock {
            d.symbol = s.symbol; d.operationType = s.operationType; d.quantity = s.quantity; d.price = s.buyPrice
            d.fee = s.fee; d.type = s.type; d.sector = s.sector ?? ""; d.notes = s.notes ?? ""; d.date = s.date
            d.currentPrice = s.currentPrice
        }
        if let c = editingCrypto {
            d.symbol = c.cryptoSymbol; d.operationType = c.transactionType; d.quantity = c.quantity; d.price = c.pricePerUnit
            d.fee = c.fee; d.exchangePlatform = c.exchangePlatform ?? ""; d.notes = c.notes ?? ""; d.isStablecoin = c.isStablecoin; d.date = c.date
        }
        if isCrypto { d.type = "crypto" }
        draft = d
        editingId = editingStock?.id ?? editingCrypto?.id
        // Crypto starts empty: "1 BTC" is never a sensible default
        quantityText = d.quantity > 0 ? AmountMath.editable(AmountMath.decimal(d.quantity), maxDecimals: isCrypto ? 8 : 6) : (isCrypto ? "" : "1")
        if d.price > 0 { priceText = Fmt.editable(d.price, digits: 0...8) }
        if d.fee > 0 { feeText = Fmt.editable(d.fee, digits: 0...2) }
    }

    var isSell: Bool { draft.operationType == .sell }
    var maxDecimals: Int { isCrypto ? 8 : 6 }
    var qty: Double { AmountMath.parse(quantityText).map(AmountMath.double) ?? 0 }
    /// Unit shown next to the amount ("BTC", "acciones").
    var unitLabel: String { isCrypto ? (draft.symbol.nilIfEmpty?.uppercased() ?? "") : String(localized: "acciones") }
    var unitPrice: Double? { price > 0 ? price : nil }
    var sellAvailable: Double? { isSell ? maxSell : nil }
    var price: Double { num(priceText) ?? 0 }
    var fee: Double { num(feeText) ?? 0 }
    var total: Double { isSell ? qty * price - fee : qty * price + fee }
    var maxSell: Double? { holding?.quantity }
    var overMax: Bool { isSell && maxSell.map { qty > $0 + 1e-9 } ?? false }
    var estimatedProfit: Double? { guard isSell, let h = holding else { return nil }; return qty * (price - h.avgPrice) - fee }
    var newAverage: Double? {
        guard !isSell, price > 0, let h = holding, h.quantity + qty > 0 else { return nil }
        return (h.quantity * h.avgPrice + qty * price) / (h.quantity + qty)
    }
    var canSubmit: Bool { !draft.symbol.trimmingCharacters(in: .whitespaces).isEmpty && qty > 0 && price > 0 && !overMax && !isSaving }
    var ctaTitle: String {
        if overMax { return String(localized: "Solo tienes \(Fmt.quantity(maxSell ?? 0, crypto: isCrypto))") }
        let sym = draft.symbol.isEmpty ? "" : " " + draft.symbol.uppercased()
        let verb = editingId != nil ? String(localized: "Guardar") : (isSell ? String(localized: "Vender") : String(localized: "Comprar"))
        let amount = AmountMath.editable(AmountMath.parse(quantityText) ?? 0, maxDecimals: maxDecimals)
        return "\(verb) \(amount)\(sym) · \(Fmt.money(total))"
    }

    // MARK: Sector (category id of type "sector"; old records may hold the raw name)
    private(set) var sectors: [FinancialCategory] = []
    var sectorId: String? {
        get { draft.sector.nilIfEmpty }
        set { draft.sector = newValue ?? "" }
    }
    var sectorName: String? {
        guard let raw = draft.sector.nilIfEmpty else { return nil }
        return sectors.first { $0.id == raw }?.name ?? SectorNames.label(raw)
    }

    // MARK: Exchange (crypto; category id of type "exchange", old records may hold the raw name)
    private(set) var exchanges: [FinancialCategory] = []
    var exchangeId: String? {
        get { draft.exchangePlatform.nilIfEmpty }
        set { draft.exchangePlatform = newValue ?? "" }
    }
    var exchangeName: String? {
        guard let raw = draft.exchangePlatform.nilIfEmpty else { return nil }
        return exchanges.first { $0.id == raw }?.name ?? (UUID(uuidString: raw) == nil ? raw : nil)
    }

    /// Sectors for stocks, exchanges for crypto.
    func loadCategories() async {
        guard let catalog else { return }
        if isCrypto {
            guard exchanges.isEmpty else { return }
            exchanges = ((try? await catalog.categories(type: "exchange")) ?? [])
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return
        }
        guard sectors.isEmpty else { return }
        let list = (try? await catalog.categories(type: "sector")) ?? []
        sectors = list.map { c in
            var c = c
            // Global sectors share codes with expense categories (TRANSPORT, UTILITIES): name them by sector
            if c.isGlobal { c.name = SectorNames.byKey[c.code.uppercased()] ?? SectorNames.label(c.name) }
            return c
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Exchange rate (prices are in USD; a non-USD account is debited/credited at this rate)
    struct RateEditRequest: Identifiable { var id: String { code }; let code: String; let preview: Double? }
    var rateEditRequest: RateEditRequest?
    private(set) var quotes: [String: RateQuote] = [:]
    var catalogRepository: CatalogRepository? { catalog }

    var accountCode: String { accounts.first { $0.id == draft.accountId }?.code.uppercased() ?? "USD" }
    /// Only on create: the account picker (and so the debited currency) is hidden when editing.
    var showsRateCard: Bool { editingId == nil && !accounts.isEmpty && accountCode != "USD" }
    var dayRate: Double? { quotes[accountCode]?.rate }
    var usedRate: Double? { draft.manualRates[accountCode] ?? dayRate }
    var isManualRate: Bool { draft.manualRates[accountCode] != nil }
    var totalInAccountCurrency: Double? {
        guard showsRateCard, let r = usedRate, r > 0 else { return nil }
        return total * r
    }
    var rateSourceText: String {
        if isManualRate { return String(localized: "Tu tasa no cambia la de otros movimientos") }
        return RatesViewModel.sourceText(quotes[accountCode]) + (quotes[accountCode] == nil ? "" : String(localized: " · hoy"))
    }

    func loadRate() async {
        guard let catalog, showsRateCard, quotes[accountCode] == nil else { return }
        quotes.merge(await LoadTransactionRatesUseCase(catalog: catalog)([accountCode])) { _, new in new }
    }
    func editRate() { rateEditRequest = RateEditRequest(code: accountCode, preview: totalInAccountCurrency) }
    func useDayRate() { draft.manualRates[accountCode] = nil }
    func applyManual(_ code: String, _ v: Double) { draft.manualRates[code] = v }
    func saveGlobal(_ code: String, _ v: Double) async {
        guard let catalog else { return }
        do {
            try await catalog.saveUSDRate(code: code, rate: v, date: draft.date)
            quotes[code] = RateQuote(code: code, rate: v, source: .saved)
            draft.manualRates[code] = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func loadAccounts() async {
        guard let catalog, accounts.isEmpty else { return }
        accounts = (try? await catalog.accountBalances()) ?? []  // pickers show live balance
        if draft.accountId == nil { draft.accountId = accounts.first(where: { $0.code == "USD" })?.id ?? accounts.first?.id }
    }

    func submit() async -> Bool {
        draft.quantity = qty; draft.price = price; draft.fee = fee
        // Only the selected account's rate matters; drop overrides left from a previous account choice
        draft.manualRates = draft.manualRates.filter { $0.key == accountCode }
        if !isSell, draft.currentPrice == nil { draft.currentPrice = price }
        guard !draft.symbol.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = ValidationError.missingSymbol.localizedDescription; return false }
        guard draft.quantity > 0, draft.price > 0 else { errorMessage = ValidationError.invalidAmount.localizedDescription; return false }
        isSaving = true; defer { isSaving = false }
        do {
            switch (isCrypto, editingId) {
            case (false, nil): try await stocks.create(draft)
            case (false, let id?): try await stocks.update(id: id, draft)
            case (true, nil): try await crypto.create(draft)
            case (true, let id?): try await crypto.update(id: id, draft)
            }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    private func num(_ s: String) -> Double? { RateParsing.parse(s) }
}
