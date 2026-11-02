import Foundation

// Remote repository implementations over the Vexia REST API.

final class RemoteAuthRepository: AuthRepository {
    private let http: HTTPClient
    private let api: APIClient
    private let tokens: TokenStore

    init(api: APIClient, tokens: TokenStore) { self.http = api; self.api = api; self.tokens = tokens }

    var hasStoredSession: Bool { tokens.hasValidTokens }

    func login(email: String, password: String) async throws -> AuthSession {
        try persist(Mappers.session(try await http.post("/auth/login", body: ["email": .string(email), "password": .string(password)])["data"]))
    }

    func register(email: String, password: String, firstName: String, lastName: String) async throws -> AuthSession {
        let body: JSON = ["email": .string(email), "password": .string(password), "firstName": .string(firstName), "lastName": .string(lastName)]
        return try persist(Mappers.session(try await http.post("/auth/register", body: body)["data"]))
    }

    func refreshSession() async -> Bool { await api.refreshTokens() }

    func currentUser() async throws -> User { Mappers.user(try await http.get("/auth/me")["data"]) }

    func logout() async {
        if let rt = tokens.refreshToken { _ = try? await http.post("/auth/logout", body: ["refreshToken": .string(rt)]) }
        tokens.clearAll()
    }

    func forgotPassword(email: String) async throws {
        _ = try await http.post("/auth/forgot-password", body: ["email": .string(email)])
    }

    func loginWithGoogle(idToken: String) async throws -> AuthSession {
        try persist(Mappers.session(try await http.post("/auth/google", body: ["idToken": .string(idToken)])["data"]))
    }

    private func persist(_ s: AuthSession) -> AuthSession {
        tokens.save(access: s.tokens.accessToken, refresh: s.tokens.refreshToken, userId: s.user.id)
        return s
    }
}

final class RemoteTransactionsRepository: TransactionsRepository {
    private let http: HTTPClient
    init(http: HTTPClient) { self.http = http }

    private func dateQuery(_ f: TransactionFilter) -> [String: String?] {
        guard let (s, e) = f.dateRange() else { return [:] }
        return ["startDate": DateCoding.dayString(s), "endDate": DateCoding.dayString(e)]
    }

    func list(filter f: TransactionFilter, page: Int, limit: Int) async throws -> Page<Transaction> {
        var q: [String: String?] = ["page": String(page), "limit": String(limit), "sortBy": "date", "sortOrder": "desc",
                                    "type": f.type?.rawValue, "categoryId": f.categoryId, "accountId": f.accountId,
                                    "search": f.search.isEmpty ? nil : f.search]
        q.merge(dateQuery(f)) { $1 }
        let res = try await http.get("/transactions", query: q)
        return Page(items: Mappers.list(res, keys: "transactions").map(Mappers.transaction),
                    pagination: Mappers.pagination(res["data"]["pagination"].isNull ? res["pagination"] : res["data"]["pagination"]))
    }

    func create(_ d: TransactionDraft) async throws -> Transaction {
        Mappers.transaction(try await http.post("/transactions", body: Mappers.transactionBody(d))["data"])
    }

    func createTransfer(_ d: TransactionDraft) async throws {
        _ = try await http.post("/transfers", body: Mappers.transferBody(d))
    }

    func update(id: Int, _ d: TransactionDraft) async throws -> Transaction {
        Mappers.transaction(try await http.put("/transactions/\(id)", body: Mappers.transactionBody(d))["data"])
    }

    func delete(id: Int) async throws { _ = try await http.delete("/transactions/\(id)") }

    func dependencies(id: Int) async throws -> TransactionDependencies {
        Mappers.dependencies(try await http.get("/transactions/\(id)/dependencies")["data"])
    }

    func summary(filter: TransactionFilter) async throws -> TransactionSummary {
        var q = dateQuery(filter); q["accountId"] = filter.accountId
        return Mappers.summary(try await http.get("/transactions/summary", query: q)["data"])
    }
}

/// Categories, accounts, currencies & rates.
final class RemoteCatalogRepository: CatalogRepository {
    private let http: HTTPClient
    init(http: HTTPClient) { self.http = http }

    func categories(type: String?) async throws -> [FinancialCategory] {
        if let type { return try await fetchCategories(type: type) }
        // The endpoint caps at 50 (no paging params) and "all" also returns currency/sector/exchange
        // categories, so user categories late in the alphabet were cut off. Fetch only what forms use.
        async let expense = fetchCategories(type: "expense")
        async let income = fetchCategories(type: "income")
        var seen = Set<String>()
        return try await (expense + income).filter { seen.insert($0.id).inserted }
    }

    private func fetchCategories(type: String) async throws -> [FinancialCategory] {
        let res = try await http.get("/user/categories", query: ["includeGlobal": "true", "includeUser": "true", "onlyActive": "true", "type": type])
        return res["data"]["categories"].array.map(Mappers.category)
    }

    func createCategory(name: String, icon: String, type: String) async throws {
        _ = try await http.post("/user/categories", body: ["name": .string(name), "icon": .string(icon), "type": .string(type)])
    }

    func accounts() async throws -> [Account] {
        Mappers.list(try await http.get("/accounts", query: ["page": "1", "limit": "100", "isActive": "true"])).map(Mappers.account)
    }

    func accountBalances() async throws -> [Account] {
        Mappers.list(try await http.get("/accounts/balances", query: ["isActive": "true"])).map(Mappers.account)
    }

    func currencyPreferences() async throws -> [CurrencyPreference] {
        Mappers.list(try await http.get("/user/currency-preferences")).map(Mappers.currencyPreference)
    }

    func countryRates() async throws -> [CountryRate] {
        Mappers.list(try await http.get("/country-rates")).map(Mappers.countryRate)
    }

    /// Falls back to the inverse pair when the direct one is missing.
    func exchangeRate(from: String, to: String) async throws -> Double? {
        func fetch(_ a: String, _ b: String) async throws -> Double? {
            Mappers.firstRate(try await http.get("/exchange-rates", query: ["fromCurrency": a, "toCurrency": b, "limit": "1"]))
        }
        if from == to { return 1 }
        if let r = try await fetch(from, to), r > 0 { return r }
        if let r = try await fetch(to, from), r > 0 { return 1 / r }
        return nil
    }

    func storedUSDRate(code: String) async throws -> Double? { try await exchangeRate(from: "USD", to: code.uppercased()) }

    func externalUSDRate(code: String) async throws -> Double? {
        Mappers.firstRate(try await http.get("/exchange-rates/fetch-from-external", query: ["currency": code.uppercased()]))
    }

    func saveUSDRate(code: String, rate: Double, date: Date) async throws {
        _ = try await http.post("/exchange-rates", body: ["fromCurrency": "USD", "toCurrency": .string(code.uppercased()),
                                                          "rate": .number(rate), "date": .string(DateCoding.dayString(date))])
    }
}

final class RemoteDashboardRepository: DashboardRepository {
    private let http: HTTPClient
    init(http: HTTPClient) { self.http = http }

    func overview() async throws -> DashboardOverview { Mappers.overview(try await http.get("/dashboard/overview")["data"]) }

    func cashFlow(period: String, groupBy: String) async throws -> CashFlow {
        Mappers.cashFlow(try await http.get("/dashboard/cash-flow", query: ["period": period, "groupBy": groupBy])["data"])
    }

    func spending(start: Date, end: Date) async throws -> SpendingAnalysis {
        Mappers.spending(try await http.get("/dashboard/spending-analysis", query: [
            "startDate": DateCoding.dayString(start), "endDate": DateCoding.dayString(end), "categoryType": "expense"])["data"])
    }

    func performance() async throws -> PortfolioPerformance {
        Mappers.performance(try await http.get("/dashboard/performance", query: [
            "period": "all", "includeInvestments": "true", "includeCrypto": "true"])["data"])
    }
}

final class RemoteInvestmentsRepository: InvestmentsRepository {
    private let http: HTTPClient
    init(http: HTTPClient) { self.http = http }

    func positions() async throws -> [StockPosition] {
        Mappers.list(try await http.get("/investments/positions"), keys: "positions").map(Mappers.position)
    }
    func operations(page: Int) async throws -> Page<Investment> {
        let res = try await http.get("/investments", query: ["page": String(page), "limit": "20"])
        return Page(items: Mappers.list(res, keys: "investments").map(Mappers.investment), pagination: Mappers.pagination(res["data"]["pagination"]))
    }
    func pnl() async throws -> [AssetPnL] { Mappers.list(try await http.get("/investments/pnl")).map(Mappers.assetPnL) }
    func pnlSummary() async throws -> PnLSummary { Mappers.pnlSummary(try await http.get("/investments/pnl/summary")["data"]) }
    func sales() async throws -> [SaleRecord] {
        Mappers.list(try await http.get("/investments/sales-history", query: ["page": "1", "limit": "50"])).map(Mappers.sale)
    }
    func create(_ d: InvestmentDraft) async throws { _ = try await http.post("/investments", body: Mappers.investmentBody(d, isUpdate: false)) }
    func update(id: Int, _ d: InvestmentDraft) async throws { _ = try await http.put("/investments/\(id)", body: Mappers.investmentBody(d, isUpdate: true)) }
    func delete(id: Int) async throws { _ = try await http.delete("/investments/\(id)") }
    func updatePrices() async throws -> PriceUpdateResult {
        Mappers.priceUpdate(try await http.put("/investments/update-prices", body: ["forceUpdate": true]))
    }
}

final class RemoteCryptoRepository: CryptoRepository {
    private let http: HTTPClient
    init(http: HTTPClient) { self.http = http }

    func portfolio() async throws -> CryptoPortfolio { Mappers.cryptoPortfolio(try await http.get("/crypto/portfolio")["data"]) }
    func positions() async throws -> [CryptoPosition] { Mappers.list(try await http.get("/crypto/positions")).map(Mappers.cryptoPosition) }
    func transactions(page: Int) async throws -> Page<CryptoTransaction> {
        let res = try await http.get("/crypto/transactions", query: ["page": String(page), "limit": "20"])
        return Page(items: Mappers.list(res).map(Mappers.cryptoTransaction), pagination: Mappers.pagination(res["data"]["pagination"]))
    }
    func pnl() async throws -> [AssetPnL] { Mappers.list(try await http.get("/crypto/pnl")).map(Mappers.assetPnL) }
    func sales() async throws -> [SaleRecord] {
        Mappers.list(try await http.get("/crypto/sales-history", query: ["page": "1", "limit": "50"])).map(Mappers.sale)
    }
    func create(_ d: InvestmentDraft) async throws { _ = try await http.post("/crypto/transactions", body: Mappers.cryptoBody(d, isUpdate: false)) }
    func update(id: Int, _ d: InvestmentDraft) async throws { _ = try await http.put("/crypto/transactions/\(id)", body: Mappers.cryptoBody(d, isUpdate: true)) }
    func delete(id: Int) async throws { _ = try await http.delete("/crypto/transactions/\(id)") }
    func updatePrices() async throws -> PriceUpdateResult {
        Mappers.priceUpdate(try await http.put("/crypto/update-prices", body: ["forceUpdate": true]))
    }
}

final class RemoteBudgetRepository: BudgetRepository {
    private let http: HTTPClient
    init(http: HTTPClient) { self.http = http }

    func budgets() async throws -> [Budget] {
        Mappers.list(try await http.get("/budgets", query: ["page": "1", "limit": "50"]), keys: "budgets").map(Mappers.budget)
    }
    func progress(budgetId: String) async throws -> BudgetProgress {
        Mappers.progress(try await http.get("/budgets/\(budgetId)/progress")["data"])
    }
    func snapshots(budgetId: String) async throws -> [BudgetSnapshot] {
        Mappers.list(try await http.get("/budgets/\(budgetId)/snapshots", query: ["page": "1", "limit": "20"])).map(Mappers.snapshot)
    }
    func createSnapshot(budgetId: String) async throws {
        _ = try await http.post("/budgets/\(budgetId)/snapshot", body: ["trigger": "manual"])
    }
    func deleteSnapshot(budgetId: String, snapshotId: String) async throws {
        _ = try await http.delete("/budgets/\(budgetId)/snapshots/\(snapshotId)")
    }
    /// Single-item edit: pre-snapshot → PUT item → post-snapshot.
    func updateItemTarget(budgetId: String, itemId: String, target: Double) async throws {
        _ = try? await http.post("/budgets/\(budgetId)/snapshot", body: ["trigger": "budget_edit_pre"])
        _ = try await http.put("/budgets/\(budgetId)/items/\(itemId)", body: ["targetAmount": .number(target)])
        _ = try? await http.post("/budgets/\(budgetId)/snapshot", body: ["trigger": "budget_edit_post"])
    }
    func delete(budgetId: String) async throws { _ = try await http.delete("/budgets/\(budgetId)") }
}

/// HTTP adapter of the budget agent (MCP `/chat` + `/interaction`, not enveloped).
final class HTTPBudgetAgent: BudgetAgent {
    private let http: HTTPClient
    init(http: HTTPClient) { self.http = http }

    private func url(_ path: String) -> URL { URL(string: AppConfig.mcpBaseURL.trimmingCharacters(in: .init(charactersIn: "/")) + path)! }
    private func ctx(_ c: AgentContext) -> JSON {
        .compact(["userCurrency": .string(c.userCurrency), "locale": .string(c.locale), "userName": .from(c.userName)])
    }

    func send(message: String, sessionId: String?, context: AgentContext) async throws -> AgentReply {
        let body: JSON = .compact(["message": .string(message), "sessionId": .from(sessionId), "context": ctx(context)])
        return Mappers.agentReply(try await http.send(.post, "/chat", query: [:], body: body, absoluteURL: url("/chat"), timeout: 120))
    }

    func interact(sessionId: String, interactionId: String, value: JSON, widgetType: String?, context: AgentContext) async throws -> AgentReply {
        let body: JSON = ["sessionId": .string(sessionId),
                          "interaction": .compact(["interactionId": .string(interactionId), "value": value,
                                                   "widgetType": .from(widgetType), "context": ctx(context)])]
        return Mappers.agentReply(try await http.send(.post, "/interaction", query: [:], body: body, absoluteURL: url("/interaction"), timeout: 120))
    }

    func endSession(_ sessionId: String) async {
        _ = try? await http.send(.delete, "/session", query: [:], body: nil, absoluteURL: url("/session/\(sessionId)"), timeout: nil)
    }
}
