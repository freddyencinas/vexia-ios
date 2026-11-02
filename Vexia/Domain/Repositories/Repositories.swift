import Foundation

// Repository contracts (Domain). Implementations live in Data/Repositories.

protocol AuthRepository: AnyObject, Sendable {
    var hasStoredSession: Bool { get }
    func login(email: String, password: String) async throws -> AuthSession
    func register(email: String, password: String, firstName: String, lastName: String) async throws -> AuthSession
    func refreshSession() async -> Bool
    func currentUser() async throws -> User
    func logout() async
    /// POST /auth/forgot-password — always succeeds server-side (anti-enumeration).
    func forgotPassword(email: String) async throws
    /// POST /auth/google — exchanges a Google ID token for a Vexia session (creates/links the user).
    func loginWithGoogle(idToken: String) async throws -> AuthSession
}

protocol TransactionsRepository: AnyObject, Sendable {
    func list(filter: TransactionFilter, page: Int, limit: Int) async throws -> Page<Transaction>
    func create(_ draft: TransactionDraft) async throws -> Transaction
    /// Same-currency transfer (POST /transfers).
    func createTransfer(_ draft: TransactionDraft) async throws
    func update(id: Int, _ draft: TransactionDraft) async throws -> Transaction
    func delete(id: Int) async throws
    func dependencies(id: Int) async throws -> TransactionDependencies
    func summary(filter: TransactionFilter) async throws -> TransactionSummary
}

protocol CatalogRepository: AnyObject, Sendable {
    func categories(type: String?) async throws -> [FinancialCategory]
    // periphery:ignore - pending: user-defined categories
    func createCategory(name: String, icon: String, type: String) async throws
    func accounts() async throws -> [Account]
    func accountBalances() async throws -> [Account]
    func currencyPreferences() async throws -> [CurrencyPreference]
    func countryRates() async throws -> [CountryRate]
    func exchangeRate(from: String, to: String) async throws -> Double?
    /// USD→code from DB (`/exchange-rates`, inverse fallback) or nil.
    func storedUSDRate(code: String) async throws -> Double?
    /// USD→code from the external provider (`/exchange-rates/fetch-from-external`).
    func externalUSDRate(code: String) async throws -> Double?
    /// Persists USD→code globally (`POST /exchange-rates`).
    func saveUSDRate(code: String, rate: Double, date: Date) async throws
}

protocol DashboardRepository: AnyObject, Sendable {
    func overview() async throws -> DashboardOverview
    func cashFlow(period: String, groupBy: String) async throws -> CashFlow
    func spending(start: Date, end: Date) async throws -> SpendingAnalysis
    func performance() async throws -> PortfolioPerformance
}

protocol InvestmentsRepository: AnyObject, Sendable {
    func positions() async throws -> [StockPosition]
    func operations(page: Int) async throws -> Page<Investment>
    func pnl() async throws -> [AssetPnL]
    func pnlSummary() async throws -> PnLSummary
    func sales() async throws -> [SaleRecord]
    func create(_ draft: InvestmentDraft) async throws
    func update(id: Int, _ draft: InvestmentDraft) async throws
    func delete(id: Int) async throws
    func updatePrices() async throws
}

protocol CryptoRepository: AnyObject, Sendable {
    func portfolio() async throws -> CryptoPortfolio
    func positions() async throws -> [CryptoPosition]
    func transactions(page: Int) async throws -> Page<CryptoTransaction>
    func pnl() async throws -> [AssetPnL]
    func sales() async throws -> [SaleRecord]
    func create(_ draft: InvestmentDraft) async throws
    func update(id: Int, _ draft: InvestmentDraft) async throws
    func delete(id: Int) async throws
    func updatePrices() async throws
}

protocol BudgetRepository: AnyObject, Sendable {
    func budgets() async throws -> [Budget]
    func progress(budgetId: String) async throws -> BudgetProgress
    func snapshots(budgetId: String) async throws -> [BudgetSnapshot]
    func createSnapshot(budgetId: String) async throws
    func deleteSnapshot(budgetId: String, snapshotId: String) async throws
    func updateItemTarget(budgetId: String, itemId: String, target: Double) async throws
    func delete(budgetId: String) async throws
}

/// Budget AI agent (MCP). Abstracted so HTTP / WebSocket / other agent backends are swappable.
protocol BudgetAgent: AnyObject, Sendable {
    func send(message: String, sessionId: String?, context: AgentContext) async throws -> AgentReply
    func interact(sessionId: String, interactionId: String, value: JSON, widgetType: String?, context: AgentContext) async throws -> AgentReply
    func endSession(_ sessionId: String) async
}

nonisolated struct AgentContext: Hashable, Sendable {
    var userCurrency: String
    var locale: String
    var userName: String?
}

/// Local preferences and secure settings.
protocol SettingsRepository: AnyObject, Sendable {
    var biometricEnabled: Bool { get set }
    var themeMode: String { get set } // system | light | dark
    var language: String { get set }  // es | en
    var hasPIN: Bool { get }
    func setPIN(_ pin: String?)
    func verifyPIN(_ pin: String) -> Bool
    var llmAPIKey: String? { get set }
}

/// Google identity port. Returns a Google ID token, or nil if the user cancelled.
/// Adapter in Data (OAuth 2.0 + PKCE via ASWebAuthenticationSession) — no Google SDK in Domain.
protocol GoogleIdentityProvider: AnyObject, Sendable {
    func signIn() async throws -> String?
}

/// Device biometric authentication port (LocalAuthentication adapter in Data).
protocol BiometricAuthenticator: AnyObject, Sendable {
    var isAvailable: Bool { get }
    var biometryName: String { get }
    func authenticate(reason: String) async -> Bool
}
