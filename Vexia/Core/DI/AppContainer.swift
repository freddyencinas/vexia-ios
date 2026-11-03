import SwiftUI

/// Composition root. The ONLY place that knows concrete Data implementations / AI SDKs.
/// Composition root: the only place that knows concrete implementations.
@Observable
final class AppContainer {
    let tokens: TokenStore
    let api: APIClient

    let auth: AuthRepository
    let transactions: TransactionsRepository
    let catalog: CatalogRepository
    let dashboard: DashboardRepository
    let investments: InvestmentsRepository
    let crypto: CryptoRepository
    let budgets: BudgetRepository
    let budgetAgent: BudgetAgent
    let settings: SettingsRepository
    let biometrics: BiometricAuthenticator
    let google: GoogleIdentityProvider

    let prompts: PromptRepository
    let llm: LLMProvider
    let makeTranscriber: () -> SpeechTranscriber
    let usage: UsageStatsUseCase

    init(secure: SecureStore = KeychainStore()) {
        tokens = TokenStore(store: secure)
        api = APIClient(tokens: tokens)
        let settings = LocalSettingsRepository(secure: secure)
        self.settings = settings
        auth = RemoteAuthRepository(api: api, tokens: tokens)
        transactions = RemoteTransactionsRepository(http: api)
        catalog = RemoteCatalogRepository(http: api)
        dashboard = RemoteDashboardRepository(http: api)
        investments = RemoteInvestmentsRepository(http: api)
        crypto = RemoteCryptoRepository(http: api)
        budgets = RemoteBudgetRepository(http: api)
        budgetAgent = HTTPBudgetAgent(http: api)
        biometrics = DeviceBiometricAuthenticator()
        google = GoogleOAuthProvider(clientID: AppConfig.googleIOSClientID)
        prompts = RemotePromptRepository()
        // AI provider chain: cloud (vision-capable) → Apple on-device fallback for text.
        llm = FallbackLLMProvider([
            CloudflareLLMProvider(apiKey: { settings.llmAPIKey }),
            AppleFoundationModelsProvider(),
        ])
        makeTranscriber = { AppleSpeechTranscriber() }
        usage = UsageStatsUseCase(repo: transactions, store: UserDefaultsUsageStatsStore())
        api.languageCode = settings.language
    }

    // MARK: Use case factories
    var login: LoginUseCase { .init(repo: auth) }
    var register: RegisterUseCase { .init(repo: auth) }
    var googleLogin: GoogleLoginUseCase { .init(google: google, repo: auth) }
    var restoreSession: RestoreSessionUseCase { .init(repo: auth, settings: settings) }
    var saveTransaction: SaveTransactionUseCase { .init(repo: transactions, usage: usage) }
    var deleteTransaction: DeleteTransactionUseCase { .init(repo: transactions) }
    var loadDashboard: LoadDashboardUseCase { .init(repo: dashboard) }
    var classifyTransaction: ClassifyTransactionUseCase { .init(llm: llm, prompts: prompts) }
    var consultSpending: ConsultSpendingUseCase { .init(dashboard: dashboard, catalog: catalog) }
    var proposeTransaction: ProposeTransactionUseCase {
        .init(classify: classifyTransaction, catalog: catalog, usage: usage.cached, language: settings.language)
    }
}

extension EnvironmentValues {
    @Entry var container: AppContainer? = nil
}
