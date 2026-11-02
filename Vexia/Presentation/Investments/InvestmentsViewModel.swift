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

    init(stocks: InvestmentsRepository, crypto: CryptoRepository) { stocksRepo = stocks; cryptoRepo = crypto }

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
        // /crypto/pnl returns the exchange's category UUID instead of its name — never show IDs as chips.
        Array(Set((cryptoOps.compactMap { $0.exchangePlatform?.nilIfEmpty } + pnl.compactMap { $0.exchange?.nilIfEmpty })
            .filter { UUID(uuidString: $0) == nil })).sorted()
    }

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
            let groups = Dictionary(grouping: h, by: { $0.sector?.nilIfEmpty ?? String(localized: "Otros") })
            return groups.map { ($0.key, $0.value.reduce(0) { $0 + ($1.value ?? $1.invested) } / total) }.sorted { $0.1 > $1.1 }
        case .crypto:
            let stable = h.filter(\.isStablecoin).reduce(0) { $0 + ($1.value ?? $1.invested) }
            return [(String(localized: "Volátil"), (total - stable) / total), (String(localized: "Stablecoins"), stable / total)].filter { $0.1 > 0 }
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
    var quantityText = ""
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
        quantityText = d.quantity > 0 ? Fmt.editable(d.quantity, digits: 0...8) : "1"
        if d.price > 0 { priceText = Fmt.editable(d.price, digits: 0...8) }
        if d.fee > 0 { feeText = Fmt.editable(d.fee, digits: 0...2) }
    }

    var isSell: Bool { draft.operationType == .sell }
    var qty: Double { num(quantityText) ?? 0 }
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
        return "\(verb) \(Fmt.grouped(qty, decimals: qty == qty.rounded() ? 0 : 4))\(sym) · \(Fmt.money(total))"
    }

    func step(_ delta: Double) {
        let v = max(isCrypto ? 0 : 1, qty + delta)
        quantityText = Fmt.editable(v, digits: 0...8)
    }

    func loadAccounts() async {
        guard let catalog, accounts.isEmpty else { return }
        accounts = (try? await catalog.accountBalances()) ?? []  // pickers show live balance
        if draft.accountId == nil { draft.accountId = accounts.first(where: { $0.code == "USD" })?.id ?? accounts.first?.id }
    }

    func submit() async -> Bool {
        draft.quantity = qty; draft.price = price; draft.fee = fee
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
