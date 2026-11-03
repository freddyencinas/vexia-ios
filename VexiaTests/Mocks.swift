import Foundation
@testable import Vexia

final class MockLLM: LLMProvider {
    let id = "mock"
    var response: String
    var error: Error?
    private(set) var lastSystem: String?
    private(set) var lastPrompt: String?
    private(set) var usedImage = false
    init(response: String = "{}", error: Error? = nil) { self.response = response; self.error = error }
    func infer(prompt: String, system: String) async throws -> String {
        lastPrompt = prompt; lastSystem = system
        if let error { throw error }
        return response
    }
    func infer(prompt: String, system: String, imageJPEG: Data) async throws -> String {
        usedImage = true
        return try await infer(prompt: prompt, system: system)
    }
}

final class MockPrompts: PromptRepository {
    func prompt(id: String, language: String) async throws -> PromptTemplate {
        PromptTemplate(id: id, version: "t", language: language,
                       fullPrompt: "EXP:\n{{EXPENSE_CATEGORIES}}\nINC:\n{{INCOME_CATEGORIES}}\nACC:\n{{ACCOUNTS}}\nParse: \"{{TEXT}}\"")
    }
}

final class MockTransactionsRepo: TransactionsRepository {
    var created: [TransactionDraft] = []
    var deps = TransactionDependencies(hasDependencies: false, blockDeletion: false, wouldCauseNegativeBalance: false, message: "", affectedCount: 0)
    private(set) var searches: [String] = []
    var items: [Transaction] = []
    /// Behaves like URLSession: a cancelled caller task aborts the request with URLError.cancelled.
    func list(filter: TransactionFilter, page: Int, limit: Int) async throws -> Page<Transaction> {
        searches.append(filter.search)
        try? await Task.sleep(for: .milliseconds(50))
        if Task.isCancelled { throw APIError.from(urlError: URLError(.cancelled)) }
        return Page(items: items, pagination: .init())
    }
    var transfers: [TransactionDraft] = []
    func create(_ d: TransactionDraft) async throws -> Transaction { created.append(d); return Fixtures.tx(id: 1) }
    func createTransfer(_ d: TransactionDraft) async throws { transfers.append(d) }
    func update(id: Int, _ d: TransactionDraft) async throws -> Transaction { Fixtures.tx(id: id) }
    private(set) var deleted: [Int] = []
    func delete(id: Int) async throws { deleted.append(id) }
    func dependencies(id: Int) async throws -> TransactionDependencies { deps }
    func summary(filter: TransactionFilter) async throws -> TransactionSummary { .init(totalIncome: 0, totalExpenses: 0, netAmount: 0, transactionCount: 0) }
}

final class MockAuthRepo: AuthRepository {
    var hasStoredSession = true
    var refreshOK = true
    var meError: Error?
    private(set) var loggedOut = false
    func login(email: String, password: String) async throws -> AuthSession { .init(user: Fixtures.user, tokens: .init(accessToken: "a", refreshToken: "r")) }
    func register(email: String, password: String, firstName: String, lastName: String) async throws -> AuthSession { try await login(email: email, password: password) }
    func refreshSession() async -> Bool { refreshOK }
    func currentUser() async throws -> User { if let meError { throw meError }; return Fixtures.user }
    func logout() async { loggedOut = true }
    func forgotPassword(email: String) async throws {}
    private(set) var googleToken: String?
    func loginWithGoogle(idToken: String) async throws -> AuthSession {
        googleToken = idToken
        return .init(user: Fixtures.user, tokens: .init(accessToken: "a", refreshToken: "r"))
    }
}

final class MockGoogle: GoogleIdentityProvider {
    var result: Result<String?, Error> = .success("google-id-token")
    func signIn() async throws -> String? { try result.get() }
}

final class MockSettings: SettingsRepository {
    var biometricEnabled = false
    var themeMode = "system"
    var language = "es"
    var pinHash: String?
    var salt: String?
    var hasPIN: Bool { pinHash != nil }
    func setPIN(_ pin: String?) {
        guard let pin else { pinHash = nil; return }
        salt = PINHasher.makeSalt(); pinHash = PINHasher.hash(pin: pin, salt: salt!)
    }
    func verifyPIN(_ pin: String) -> Bool { salt.map { PINHasher.hash(pin: pin, salt: $0) } == pinHash }
    var llmAPIKey: String?
}

final class MockCatalog: CatalogRepository {
    var prefs: [CurrencyPreference] = []
    var stored: [String: Double] = [:]
    var external: [String: Double] = [:]
    private(set) var saved: [(String, Double)] = []
    private(set) var externalCalls: [String] = []
    var categoryList = Fixtures.categories
    func categories(type: String?) async throws -> [FinancialCategory] { categoryList }
    func createCategory(name: String, icon: String, type: String) async throws {}
    func accounts() async throws -> [Account] { Fixtures.accounts }
    func accountBalances() async throws -> [Account] { Fixtures.accounts.map { var a = $0; a.currentBalance = 3258.12; return a } }
    func currencyPreferences() async throws -> [CurrencyPreference] { prefs }
    func countryRates() async throws -> [CountryRate] { [] }
    func exchangeRate(from: String, to: String) async throws -> Double? { nil }
    func storedUSDRate(code: String) async throws -> Double? { stored[code] }
    func externalUSDRate(code: String) async throws -> Double? { externalCalls.append(code); return external[code] }
    func saveUSDRate(code: String, rate: Double, date: Date) async throws { saved.append((code, rate)) }
}

final class MemoryUsageStore: UsageStatsStore, @unchecked Sendable {
    var stats: UsageStats?
    func load() -> UsageStats? { stats }
    func save(_ stats: UsageStats) { self.stats = stats }
}

enum Fixtures {
    static let user = User(id: "u1", email: "a@b.com", firstName: "Ana", lastName: "Pérez")
    static let accounts = [
        Account(id: "acc1", name: "Banco Unión", type: .checking, currencyId: "cur-bob", currencyCode: "BOB", initialBalance: 0, isFavorite: false),
        Account(id: "acc2", name: "Efectivo", type: .cash, currencyId: "cur-usd", currencyCode: "USD", initialBalance: 0, isFavorite: true),
    ]
    static let categories = [
        FinancialCategory(id: "c-food", code: "FOOD", name: "Comida", type: "expense", isGlobal: true),
        FinancialCategory(id: "c-sal", code: "SALARY", name: "Salario", type: "income", isGlobal: true),
    ]
    static func tx(id: Int, type: String, category: String? = nil, account: String? = nil, to: String? = nil, date: String) -> Transaction {
        var j: [String: JSON] = ["id": .number(Double(id)), "amount": 10, "currency": "USD", "description": "x", "date": .string(date), "type": .string(type)]
        if let category { j["categoryId"] = .string(category) }
        if type == "transfer" { j["fromAccountId"] = account.map(JSON.string) ?? .null; j["toAccountId"] = to.map(JSON.string) ?? .null }
        else if let account { j["accountId"] = .string(account) }
        return Mappers.transaction(.object(j))
    }
    static func tx(id: Int) -> Transaction {
        Mappers.transaction(["id": .number(Double(id)), "amount": 10, "currency": "USD", "description": "x", "date": "2026-10-01", "type": "expense"])
    }
}

struct Unused: Error {}

final class MockStocks: InvestmentsRepository, @unchecked Sendable {
    func positions() async throws -> [StockPosition] { [] }
    func operations(page: Int) async throws -> Page<Investment> { throw Unused() }
    func pnl() async throws -> [AssetPnL] { [] }
    func pnlSummary() async throws -> PnLSummary { throw Unused() }
    func sales() async throws -> [SaleRecord] { [] }
    func create(_ draft: InvestmentDraft) async throws {}
    func update(id: Int, _ draft: InvestmentDraft) async throws {}
    private(set) var deleted: [Int] = []
    func delete(id: Int) async throws { deleted.append(id) }
    func updatePrices() async throws -> PriceUpdateResult { PriceUpdateResult(total: 0, updated: 0) }
}

final class MockCrypto: CryptoRepository, @unchecked Sendable {
    func portfolio() async throws -> CryptoPortfolio { throw Unused() }
    func positions() async throws -> [CryptoPosition] { [] }
    func transactions(page: Int) async throws -> Page<CryptoTransaction> { throw Unused() }
    func pnl() async throws -> [AssetPnL] { [] }
    func sales() async throws -> [SaleRecord] { [] }
    func create(_ draft: InvestmentDraft) async throws {}
    func update(id: Int, _ draft: InvestmentDraft) async throws {}
    private(set) var deleted: [Int] = []
    func delete(id: Int) async throws { deleted.append(id) }
    func updatePrices() async throws -> PriceUpdateResult { PriceUpdateResult(total: 0, updated: 0) }
}
