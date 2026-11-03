import SwiftUI

@Observable
final class TransactionsListViewModel {
    var filter = TransactionFilter(period: .all)
    /// First day of the month shown (nil = all time). Design: "‹ Octubre 2026 ›".
    var month: Date? = Calendar.current.dateInterval(of: .month, for: .now)?.start
    private(set) var items: [Transaction] = []
    private(set) var summary: TransactionSummary?
    private(set) var state: Loadable<Void> = .idle
    private(set) var isLoadingMore = false
    private(set) var accounts: [Account] = []
    private(set) var categories: [FinancialCategory] = []
    private var pagination = Pagination()
    private var loadTask: Task<Void, Never>?
    private var generation = 0
    var errorMessage: String?
    var pendingDelete: Transaction?
    var deleteWarning: String?

    private let repo: TransactionsRepository
    private let catalog: CatalogRepository
    private let deleteUseCase: DeleteTransactionUseCase
    let pageSize = 30

    init(repo: TransactionsRepository, catalog: CatalogRepository, delete: DeleteTransactionUseCase) {
        self.repo = repo; self.catalog = catalog; self.deleteUseCase = delete
    }

    var sections: [(day: Date, items: [Transaction])] { TransactionGrouping.byDay(items) }
    var monthTitle: String { month.map(Fmt.monthYearES) ?? String(localized: "Todo el historial") }
    var canGoForward: Bool { month.map { $0 < Calendar.current.dateInterval(of: .month, for: .now)!.start } ?? false }
    var baseCurrency: String { summary?.currencyCode ?? items.first?.displayCurrency ?? "USD" }

    /// Totals for the summary card. Server summary when it has data, else computed from the loaded items.
    var totals: (income: Double, expenses: Double, currency: String) {
        if let s = summary, s.totalIncome + s.totalExpenses > 0 { return (s.totalIncome, s.totalExpenses, s.currencyCode ?? "USD") }
        let base = baseCurrency
        let inBase = items.filter { $0.displayCurrency == base }
        return (inBase.filter { $0.type == .income }.reduce(0) { $0 + abs($1.amount) },
                inBase.filter { $0.type == .expense }.reduce(0) { $0 + abs($1.amount) }, base)
    }

    func dayTotal(_ list: [Transaction]) -> String {
        let base = baseCurrency
        let net = list.filter { $0.displayCurrency == base && $0.type != .transfer }
            .reduce(0.0) { $0 + ($1.type == .income ? abs($1.amount) : -abs($1.amount)) }
        return net == 0 ? "" : (net > 0 ? "+" : "") + Fmt.money(net, currency: base)
    }

    func shiftMonth(_ delta: Int) {
        let start = month ?? Calendar.current.dateInterval(of: .month, for: .now)!.start
        month = Calendar.current.date(byAdding: .month, value: delta, to: start)
        Task { await reload() }
    }
    func showAllTime() { month = nil; Task { await reload() } }
    /// Search asked from outside the screen (Siri): the term may match any month.
    func search(_ term: String) { month = nil; filter.search = term; Task { await reload() } }

    private var effectiveFilter: TransactionFilter {
        var f = filter
        f.period = .all
        f.monthStart = month
        return f
    }

    func loadCatalog() async {
        guard accounts.isEmpty else { return }
        async let a = try? catalog.accounts()
        async let c = try? catalog.categories(type: nil)
        accounts = await a ?? []
        categories = await c ?? []
    }

    /// Filter/refresh entry point: drops a pending debounced search, then loads.
    func reload() async {
        loadTask?.cancel(); loadTask = nil
        await performReload()
    }

    private func performReload() async {
        generation += 1
        let mine = generation
        state = .loading
        do {
            async let page = repo.list(filter: effectiveFilter, page: 1, limit: pageSize)
            async let sum = try? repo.summary(filter: effectiveFilter)
            let p = try await page
            let s = await sum
            guard mine == generation else { return }  // a newer query superseded this one
            items = p.items; pagination = p.pagination
            summary = s
            state = .loaded(())
        } catch {
            guard mine == generation, !Self.isCancellation(error) else { return }
            state = .failed(error.localizedDescription)
        }
    }

    /// Typing restarts the timer; the task must not call `reload()` (it would cancel itself
    /// mid-request → URLError.cancelled shown as "No pudimos cargar tus movimientos").
    func scheduleReload() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.performReload()
        }
    }

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? APIError)?.code == .cancelled || (error as? URLError)?.code == .cancelled
    }

    func loadMoreIfNeeded(current: Transaction) async {
        guard pagination.hasNext, !isLoadingMore, current.id == items.last?.id else { return }
        isLoadingMore = true; defer { isLoadingMore = false }
        if let p = try? await repo.list(filter: effectiveFilter, page: pagination.page + 1, limit: pageSize) {
            let known = Set(items.map(\.id))
            items += p.items.filter { !known.contains($0.id) }
            pagination = p.pagination
        }
    }

    func requestDelete(_ tx: Transaction) async {
        switch await deleteUseCase.check(id: tx.id) {
        case .blocked(let msg): errorMessage = msg.isEmpty ? String(localized: "No se puede eliminar esta transacción") : msg
        case .warn(let msg): deleteWarning = msg; pendingDelete = tx
        case .safe: deleteWarning = nil; pendingDelete = tx
        }
    }

    /// Takes the transaction explicitly: dismissing the dialog clears `pendingDelete` before its button runs.
    func confirmDelete(_ tx: Transaction) async {
        pendingDelete = nil
        do {
            try await deleteUseCase(id: tx.id)
            withAnimation { items.removeAll { $0.id == tx.id } }
            summary = try? await repo.summary(filter: effectiveFilter)
        } catch { errorMessage = error.localizedDescription }
    }
}

/// Create/edit form (incl. FX rates strip).
@Observable
final class TransactionFormViewModel {
    var draft: TransactionDraft
    var amountText: String
    var toAmountText = ""
    var exchangeRateText = ""
    var tagInput = ""
    private(set) var accounts: [Account] = []
    private(set) var categories: [FinancialCategory] = []
    private(set) var isSaving = false
    private(set) var isLoadingCatalog = false
    var errorMessage: String?
    var infoMessage: String?
    let editingId: Int?
    let originalSnapshots: [CurrencySnapshot]
    var aiNotes: [String] = []

    // Rates strip state (USD→CODE)
    private(set) var rateCurrencies: [String] = []
    private(set) var quotes: [String: RateQuote] = [:]
    private(set) var isLoadingRates = false
    private(set) var isRefreshingRates = false
    var editingRateCode: String?
    var rateEditText = ""
    private var rateTypedByUser = false

    private let save: SaveTransactionUseCase
    private let catalog: CatalogRepository
    private let loadRates: LoadTransactionRatesUseCase
    private let usage: UsageStatsUseCase?
    private var stats: UsageStats
    /// Accounts we preselected (not the user): only these get replaced when type or stats change.
    private var autoAccountId: String?
    private var autoToAccountId: String?

    init(save: SaveTransactionUseCase, catalog: CatalogRepository, editing: Transaction? = nil, prefill: TransactionDraft? = nil,
         usage: UsageStatsUseCase? = nil) {
        self.save = save; self.catalog = catalog; self.usage = usage
        stats = usage?.cached ?? UsageStats()
        loadRates = LoadTransactionRatesUseCase(catalog: catalog)
        editingId = editing?.id
        originalSnapshots = editing?.currencySnapshots ?? []
        let initial: TransactionDraft
        if let t = editing {
            initial = TransactionDraft(type: t.type, amount: abs(t.amount), currency: t.currency, description: t.description,
                                       date: t.date, accountId: t.accountId ?? t.fromAccountId, categoryId: t.categoryId,
                                       tags: t.tags, isRecurring: t.isRecurring, toAccountId: t.toAccountId,
                                       toAmount: t.toAmount ?? 0, exchangeRate: t.exchangeRate,
                                       currencyCode: t.currencyCode ?? "")
        } else {
            initial = prefill ?? TransactionDraft()
        }
        draft = initial
        amountText = initial.amount > 0 ? Fmt.editable(initial.amount, digits: 0...2) : ""
        if initial.toAmount > 0 { toAmountText = Fmt.editable(initial.toAmount, digits: 0...2) }
        if let r = initial.exchangeRate { exchangeRateText = Fmt.editable(r, digits: 0...6); rateTypedByUser = editing != nil }
    }

    var isEditing: Bool { editingId != nil }
    var catalogRepository: CatalogRepository { catalog }
    /// Fallback order for users without history: everyday categories first, then the rest alphabetically.
    static let categoryPriority = ["FOOD", "MARKET", "TRANSPORT", "HOUSING", "UTILITIES", "HEALTHCARE", "ENTERTAINMENT", "SHOPPING",
                                   "EDUCATION", "TAXES", "SALARY", "FREELANCE", "BUSINESS", "REMITTANCE", "BONUS", "RENTAL", "INVESTMENT", "OTHER"]
    /// The user's most used categories first, then the fallback order.
    var filteredCategories: [FinancialCategory] {
        let used = stats.rankedCategoryIds(for: draft.type)
        return categories.filter { $0.type == draft.type.rawValue }.sorted { a, b in
            let ua = used.firstIndex(of: a.id) ?? Int.max, ub = used.firstIndex(of: b.id) ?? Int.max
            if ua != ub { return ua < ub }
            let ia = Self.categoryPriority.firstIndex(of: a.code.uppercased()) ?? Int.max
            let ib = Self.categoryPriority.firstIndex(of: b.code.uppercased()) ?? Int.max
            return ia == ib ? a.name < b.name : ia < ib
        }
    }
    var fromAccount: Account? { accounts.first { $0.id == draft.accountId } }
    var toAccount: Account? { accounts.first { $0.id == draft.toAccountId } }
    var needsConversion: Bool { draft.type == .transfer && fromAccount != nil && toAccount != nil && fromAccount?.currencyId != toAccount?.currencyId }

    func loadCatalog() async {
        guard accounts.isEmpty else { return }
        isLoadingCatalog = true
        // /accounts/balances: plain /accounts has no currentBalance, so pickers would show the initial balance.
        async let a = try? catalog.accountBalances()
        async let c = try? catalog.categories(type: nil)
        accounts = (await a ?? []).sorted { $0.isFavorite && !$1.isFavorite }
        categories = await c ?? []
        applyAccountDefaults()  // cached stats → instant defaults
        syncCurrency()
        isLoadingCatalog = false
        await loadRatesStrip()
        if let usage, !isEditing {
            stats = await usage.refresh()
            applyAccountDefaults()
        }
    }

    /// Last account used for this type (transfers: origin and destination), else the favorite/first.
    /// Never overrides an account the user picked or one that came prefilled (e.g. from Vexia).
    func applyAccountDefaults() {
        guard !isEditing, !accounts.isEmpty else { return }
        func existing(_ id: String?) -> String? { id.flatMap { id in accounts.first { $0.id == id }?.id } }
        if draft.accountId == nil || draft.accountId == autoAccountId {
            let id = existing(stats.lastAccountId(for: draft.type)) ?? accounts.first?.id
            draft.accountId = id; autoAccountId = id
        }
        if draft.type == .transfer, draft.toAccountId == nil || draft.toAccountId == autoToAccountId,
           let to = existing(stats.lastTransferDestinationId), to != draft.accountId {
            draft.toAccountId = to; autoToAccountId = to
        }
    }

    func syncCurrency() {
        if let a = fromAccount { draft.currency = a.currencyId; draft.currencyCode = a.code.uppercased() }
        if let t = toAccount { draft.toCurrency = t.currencyId; draft.toCurrencyCode = t.code.uppercased() }
        else { draft.toCurrency = ""; draft.toCurrencyCode = "" }
    }

    func typeChanged() {
        applyAccountDefaults()
        if let c = draft.categoryId, !filteredCategories.contains(where: { $0.id == c }) { draft.categoryId = nil }
    }

    // MARK: Rates strip

    /// Effective USD→code rate: manual ("solo esta vez") overrides stored quote.
    func rate(for code: String) -> Double? { draft.manualRates[code] ?? quotes[code]?.rate }
    func isManual(_ code: String) -> Bool { draft.manualRates[code] != nil }

    func loadRatesStrip() async {
        isLoadingRates = true; defer { isLoadingRates = false }
        var codes = await loadRates.currencies()
        // Make sure the involved account currencies are always visible.
        for c in [draft.currencyCode, draft.toCurrencyCode] where !c.isEmpty && c != "USD" && !codes.contains(c) { codes.append(c) }
        rateCurrencies = codes
        // Editing: original snapshot rates first (EditTransactionScreen behavior), then fill gaps.
        for s in originalSnapshots where s.exchangeRate > 0 {
            quotes[s.currencyCode.uppercased()] = RateQuote(code: s.currencyCode.uppercased(), rate: s.exchangeRate, source: .snapshot)
        }
        let missing = codes.filter { quotes[$0] == nil }
        quotes.merge(await loadRates(missing)) { old, _ in old }
        recomputeFX()
    }

    // periphery:ignore - pending: "refresh all rates" action in the form
    func refreshAllRates() async {
        isRefreshingRates = true; defer { isRefreshingRates = false }
        let fresh = await loadRates(rateCurrencies, forceExternal: true)
        quotes.merge(fresh) { _, new in new }
        draft.manualRates.removeAll()
        recomputeFX()
        infoMessage = fresh.isEmpty ? String(localized: "No se pudieron actualizar las tasas") : String(localized: "Tasas actualizadas (\(fresh.count))")
    }

    // periphery:ignore - pending: long-press on a rate chip to refresh it
    func refreshRate(_ code: String) async {
        if let q = await loadRates([code], forceExternal: true)[code] {
            quotes[code] = q
            draft.manualRates[code] = nil
            recomputeFX()
        }
    }

    func beginEditRate(_ code: String) {
        editingRateCode = code
        rateEditText = rate(for: code).map { Fmt.editable($0, digits: 0...4) } ?? ""
    }

    /// "Solo esta vez": only affects this transaction (sent in manualExchangeRates / customExchangeRate).
    func applyRateOnce() {
        guard let code = editingRateCode, let v = parse(rateEditText), v > 0 else { errorMessage = String(localized: "Ingresa una tasa válida"); return }
        draft.manualRates[code] = v
        editingRateCode = nil
        recomputeFX()
    }

    /// "Guardar": persists globally (POST /exchange-rates) and clears the manual override.
    func saveRateGlobally() async {
        guard let code = editingRateCode, let v = parse(rateEditText), v > 0 else { errorMessage = String(localized: "Ingresa una tasa válida"); return }
        editingRateCode = nil
        do {
            try await catalog.saveUSDRate(code: code, rate: v, date: draft.date)
            quotes[code] = RateQuote(code: code, rate: v, source: .saved)
            draft.manualRates[code] = nil
            recomputeFX()
            infoMessage = String(localized: "Tasa \(code) guardada: \(Fmt.number(v, digits: 2...4))")
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Design-review additions (rate card, editor sheet, CTA)

    struct RateEditRequest: Identifiable { var id: String { code }; let code: String; let preview: Double? }
    var rateEditRequest: RateEditRequest?

    var amountValue: Double { parse(amountText) ?? 0 }
    var accountCode: String { fromAccount?.code.uppercased() ?? (draft.currencyCode.isEmpty ? "USD" : draft.currencyCode) }
    var toCode: String { toAccount?.code.uppercased() ?? draft.toCurrencyCode }
    /// Rate card only when the account is not in USD (design: "mostrar solo lo relevante").
    var showsRateCard: Bool { draft.type != .transfer && accountCode != "USD" }
    var dayRate: Double? { quotes[accountCode]?.rate }
    var usedRate: Double? { rate(for: accountCode) }
    var equivalentUSD: Double? { guard accountCode != "USD", let r = usedRate, r > 0 else { return nil }; return amountValue / r }
    var rateSourceText: String {
        if isManual(accountCode) { return String(localized: "Tu tasa no cambia la de otros movimientos") }
        return RatesViewModel.sourceText(quotes[accountCode]) + (quotes[accountCode] == nil ? "" : String(localized: " · hoy"))
    }
    /// Other currencies the backend will snapshot this movement in.
    var alsoSavedIn: [(code: String, amount: Double, rate: Double)] {
        guard let usd = equivalentUSD ?? (accountCode == "USD" ? amountValue : nil), amountValue > 0 else { return [] }
        var out: [(String, Double, Double)] = accountCode == "USD" ? [] : [("USD", usd, 1)]
        for c in rateCurrencies where c != accountCode { if let r = rate(for: c) { out.append((c, usd * r, r)) } }
        return out
    }

    func useDayRate() { draft.manualRates[accountCode] = nil; recomputeFX() }
    func editRate(_ code: String, preview: Double?) { rateEditRequest = RateEditRequest(code: code, preview: preview) }
    func applyManual(_ code: String, _ v: Double) { draft.manualRates[code] = v; recomputeFX() }
    /// Throws so the caller (island) reports the failure.
    func saveGlobal(_ code: String, _ v: Double) async throws {
        try await catalog.saveUSDRate(code: code, rate: v, date: draft.date)
        quotes[code] = RateQuote(code: code, rate: v, source: .saved)
        draft.manualRates[code] = nil
        recomputeFX()
    }

    // Currency exchange helpers
    var dayCrossRate: Double? {
        ExchangeMath.crossRate(from: accountCode, to: toCode, quotes: quotes.mapValues(\.rate))
    }
    var fxRateValue: Double? { parse(exchangeRateText) }
    var usesDayFXRate: Bool { !rateTypedByUser }
    func useDayFXRate() { rateTypedByUser = false; recomputeFX() }
    // periphery:ignore - pending: quick-set FX rate from a suggestion
    func setFXRate(_ v: Double) { exchangeRateText = Fmt.editable(v, digits: 0...6); rateTypedByUser = true; amountChanged() }
    /// Difference in received amount vs. the day rate (positive = you receive less).
    var fxShortfall: Double? {
        guard needsConversion, !usesDayFXRate, let d = dayCrossRate, let r = fxRateValue, amountValue > 0 else { return nil }
        let diff = amountValue * d - amountValue * r
        return abs(diff) < 0.005 ? nil : diff
    }
    func swapAccounts() {
        guard draft.type == .transfer, let to = draft.toAccountId else { return }
        draft.toAccountId = draft.accountId; draft.accountId = to
        Task { await accountsChanged() }
    }

    /// Human rate label, USD-anchored when one side is USD ("1 USD = 9,96 Bs").
    func rateLabel(from: String, to: String, rate: Double) -> String {
        let sym = { (c: String) in Fmt.symbol(c) ?? c }
        if from == "USD" { return "1 USD = \(Fmt.grouped(rate)) \(sym(to))" }
        if to == "USD", rate > 0 { return "1 USD = \(Fmt.grouped(1 / rate)) \(sym(from))" }
        return "1 \(from) = \(Fmt.grouped(rate, decimals: 4)) \(to)"
    }

    var missingFields: [String] {
        var m: [String] = []
        if amountValue <= 0 { m.append(String(localized: "monto")) }
        if fromAccount == nil { m.append(String(localized: "cuenta")) }
        if draft.type == .transfer { if toAccount == nil { m.append(String(localized: "cuenta destino")) } }
        else if draft.categoryId == nil { m.append(String(localized: "categoría")) }
        return m
    }
    var ctaTitle: String {
        if !missingFields.isEmpty { return String(localized: "Falta: \(missingFields.joined(separator: ", "))") }
        let amount = Fmt.money(amountValue, currency: accountCode)
        switch draft.type {
        case .expense: return isEditing ? String(localized: "Guardar cambios · \(amount)") : String(localized: "Guardar gasto · \(amount)")
        case .income: return isEditing ? String(localized: "Guardar cambios · \(amount)") : String(localized: "Guardar ingreso · \(amount)")
        case .transfer: return needsConversion ? String(localized: "Cambiar \(amount) → \(Fmt.money(parse(toAmountText) ?? 0, currency: toCode))") : String(localized: "Transferir · \(amount)")
        }
    }
    var savedSummary: String {
        SavedBanner.summary(type: draft.type, isEditing: isEditing, isExchange: needsConversion,
                            amount: Fmt.money(amountValue, currency: accountCode), account: fromAccount?.name)
    }
    var title: String {
        if isEditing { return String(localized: "Editar") }
        switch draft.type { case .expense: return String(localized: "Nuevo gasto"); case .income: return String(localized: "Nuevo ingreso"); case .transfer: return needsConversion ? String(localized: "Cambio de divisa") : String(localized: "Transferencia") }
    }
    /// Category grid: selected/suggested first, then the rest (up to 7 + "Más").
    var gridCategories: [FinancialCategory] {
        var list = filteredCategories
        if let id = draft.categoryId, let i = list.firstIndex(where: { $0.id == id }) { list.insert(list.remove(at: i), at: 0) }
        return Array(list.prefix(7))
    }

    // MARK: Currency exchange (cross-currency transfer)

    func accountsChanged() async {
        syncCurrency()
        for c in [draft.currencyCode, draft.toCurrencyCode] where !c.isEmpty && c != "USD" && !rateCurrencies.contains(c) {
            rateCurrencies.append(c)
            if let q = await loadRates([c])[c] { quotes[c] = q }
        }
        rateTypedByUser = false
        recomputeFX()
    }

    func userEditedRate() { rateTypedByUser = true; recomputeToAmount() }

    func userEditedToAmount() {
        guard needsConversion, let a = parse(amountText), a > 0, let t = parse(toAmountText), t > 0 else { return }
        rateTypedByUser = true
        exchangeRateText = Fmt.editable(t / a, digits: 0...6)
    }

    func amountChanged() { recomputeToAmount() }

    /// Derives from→to rate from USD quotes unless the user typed one.
    private func recomputeFX() {
        guard needsConversion else { return }
        if !rateTypedByUser {
            let manualAndStored = rateCurrencies.reduce(into: [String: Double]()) { $0[$1] = rate(for: $1) }
            if let r = ExchangeMath.crossRate(from: draft.currencyCode, to: draft.toCurrencyCode, quotes: manualAndStored) {
                exchangeRateText = Fmt.editable(r, digits: 0...6)
            } else {
                Task { [weak self] in
                    guard let self, let r = try? await catalog.exchangeRate(from: draft.currencyCode, to: draft.toCurrencyCode) else { return }
                    exchangeRateText = Fmt.editable(r, digits: 0...6); recomputeToAmount()
                }
            }
        }
        recomputeToAmount()
    }

    private func recomputeToAmount() {
        guard needsConversion, let a = parse(amountText), let r = parse(exchangeRateText) else { return }
        toAmountText = Fmt.editable(a * r, digits: 0...2)
    }

    // MARK: Tags / submit

    func addTag() {
        let t = tagInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty, !draft.tags.contains(t) else { tagInput = ""; return }
        draft.tags.append(t); tagInput = ""
    }

    func submit() async -> Bool {
        syncCurrency()
        draft.amount = parse(amountText) ?? 0
        draft.toAmount = parse(toAmountText) ?? 0
        draft.exchangeRate = needsConversion ? parse(exchangeRateText) : nil
        isSaving = true; defer { isSaving = false }
        do { try await save(draft, editingId: editingId); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    /// Locale-tolerant: accepts "1.234,5" and "1,234.5".
    func parse(_ s: String) -> Double? {
        var t = s.filter { "0123456789.,".contains($0) }
        if let lastComma = t.lastIndex(of: ","), let lastDot = t.lastIndex(of: ".") {
            t = lastComma > lastDot ? t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                                    : t.replacingOccurrences(of: ",", with: "")
        } else { t = t.replacingOccurrences(of: ",", with: ".") }
        return Double(t)
    }
}
