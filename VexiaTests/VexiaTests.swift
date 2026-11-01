import Foundation
import Testing
import UIKit
@testable import Vexia

@Suite("AI: parser & prompt")
struct AIParsingTests {
    @Test func parsesFencedJSONWithStringAmount() throws {
        let raw = """
        ```json
        {"language":"es","intent":"expense","confidence":"0.9","needs_confirmation":"true",
         "form_prefill":{"type":"expense","amount":{"value":"1.234,50 Bs","currency":"BOB"},
         "description":" almuerzo ","date":{"relative":"yesterday"},"category_id":"FOOD","tags":["comida"]},
         "validation":{"missing_fields":["account_from_id"]},
         "clarifying_questions":[{"field":"account_from_id","question":"¿Con qué cuenta?"}]}
        ```
        """
        let r = try VexiaResultParser.parse(raw)
        #expect(r.intent == .expense)
        #expect(r.confidence == 0.9)
        #expect(r.needsConfirmation)
        #expect(r.form.description == "almuerzo")
        #expect(r.form.currency == "BOB")
        #expect(r.missingFields == ["account_from_id"])
        #expect(r.clarifyingQuestions.first?.question == "¿Con qué cuenta?")
        // "1.234,50" → commas become dots → "1.234.50" is not a valid Double
        #expect(r.form.amount == nil)
    }

    @Test func parsesNumericAmountAndUnknownIntent() throws {
        let r = try VexiaResultParser.parse(#"noise {"intent":"weird","form_prefill":{"amount":{"value":50}}} trailing"#)
        #expect(r.intent == .unknown)
        #expect(r.form.amount == 50)
    }

    @Test func rejectsNonObject() {
        #expect(throws: AIError.self) { try VexiaResultParser.parse("no json here") }
    }

    @Test func relativeDateResolution() {
        let now = DateCoding.parse("2026-10-15")!
        let f = VexiaResult.FormPrefill(dateRelative: "yesterday")
        #expect(DateCoding.dayString(f.resolvedDate(now: now)) == "2026-10-14")
        let iso = VexiaResult.FormPrefill(dateISO: "2026-01-02", dateRelative: "yesterday")
        #expect(DateCoding.dayString(iso.resolvedDate(now: now)) == "2026-01-02")
    }

    @Test func systemPromptStripsTextPlaceholder() {
        let t = PromptTemplate(id: "x", version: "1", language: "es",
                               fullPrompt: "A {{EXPENSE_CATEGORIES}}\n\n\n\nB {{ACCOUNTS}}\nParse: \"{{TEXT}}\"")
        let s = t.systemPrompt(expenseCategories: "- FOOD: Comida", incomeCategories: "", accounts: "- Efectivo")
        #expect(s == "A - FOOD: Comida\n\nB - Efectivo")
    }

    @Test func embeddedPromptsAreBundled() throws {
        let es = try RemotePromptRepository.embedded(id: "ExpenseIncomeClassifier", language: "es")
        let en = try RemotePromptRepository.embedded(id: "ExpenseIncomeClassifier", language: "en")
        #expect(es.fullPrompt.contains("{{EXPENSE_CATEGORIES}}"))
        #expect(en.fullPrompt.contains("{{ACCOUNTS}}"))
    }

    @Test func cloudResponseUnwrapping() throws {
        func run(_ s: String) throws -> String { let d = Data(s.utf8); return CloudflareLLMProvider.extract(try JSON.parse(d), raw: d) }
        #expect(try run(#"{"answer":"hola"}"#) == "hola")
        #expect(try run(#"{"response":"r"}"#) == "r")
        #expect(try run(#"{"result":"x"}"#) == "x")
        #expect(try run(#"{"intent":"expense","language":"es"}"#).contains("intent"))
    }
}

@Suite("Use cases")
struct UseCaseTests {
    @Test func classifyUsesPortsAndPostProcesses() async throws {
        let llm = MockLLM(response: #"{"intent":"expense","form_prefill":{"type":"expense","amount":{"value":25},"category_id":"food","account_from_id":"Efectivo","account_to_id":"Ghost Bank","description":"Pizza"}}"#)
        let uc = ClassifyTransactionUseCase(llm: llm, prompts: MockPrompts())
        let r = try await uc(text: "gasté 25 en pizza", language: "es", categories: Fixtures.categories, accounts: Fixtures.accounts)

        #expect(llm.lastPrompt == "gasté 25 en pizza")
        #expect(llm.lastSystem?.contains("- FOOD: Comida") == true)
        #expect(llm.lastSystem?.contains("- SALARY: Salario") == true)
        #expect(llm.lastSystem?.contains("{{TEXT}}") == false)
        #expect(r.form.categoryId == "c-food")      // code → id
        #expect(r.form.accountFromId == "acc2")     // name → id
        #expect(r.form.accountToId == nil)          // unknown account dropped

        let d = ClassifyTransactionUseCase.draft(from: r, accounts: Fixtures.accounts)
        #expect(d.amount == 25)
        #expect(d.currency == "cur-usd")
        #expect(d.description == "Pizza")
    }

    @Test func spokenCurrencyPicksMatchingAccount() throws {
        let r = try VexiaResultParser.parse(#"{"intent":"expense","form_prefill":{"type":"expense","amount":{"value":35,"currency":"dólares"}}}"#)
        // acc1 is BOB and listed first; acc2 is USD.
        #expect(ClassifyTransactionUseCase.draft(from: r, accounts: Fixtures.accounts).accountId == "acc2")
        let bob = try VexiaResultParser.parse(#"{"intent":"expense","form_prefill":{"amount":{"value":35,"currency":"Bs"}}}"#)
        #expect(ClassifyTransactionUseCase.draft(from: bob, accounts: Fixtures.accounts).accountId == "acc1")
    }

    @Test func classifyRejectsEmptyInput() async {
        let uc = ClassifyTransactionUseCase(llm: MockLLM(), prompts: MockPrompts())
        await #expect(throws: AIError.emptyTranscript) {
            try await uc(text: "  ", language: "es", categories: [], accounts: [])
        }
    }

    @Test func classifyReceiptUsesVisionPath() async throws {
        let llm = MockLLM(response: #"{"intent":"expense"}"#)
        _ = try await ClassifyTransactionUseCase(llm: llm, prompts: MockPrompts())(imageJPEG: Data([1, 2]), language: "es", categories: [], accounts: [])
        #expect(llm.usedImage)
        #expect(llm.lastPrompt == ClassifyTransactionUseCase.receiptPrompt)
    }

    @Test func fallbackProviderTriesNext() async throws {
        let p = FallbackLLMProvider([MockLLM(error: AIError.unavailable("down")), MockLLM(response: "ok")])
        #expect(try await p.infer(prompt: "a", system: "b") == "ok")
    }

    struct InvalidDraft: Sendable, CustomTestStringConvertible {
        var type: TransactionType; var amount: Double; var from: String?; var to: String?; var cat: String?; var expected: ValidationError
        var testDescription: String { "\(expected)" }
    }

    @Test(arguments: [
        InvalidDraft(type: .expense, amount: 0, from: "acc1", to: nil, cat: "c", expected: .invalidAmount),
        InvalidDraft(type: .expense, amount: 10, from: nil, to: nil, cat: "c", expected: .missingAccount),
        InvalidDraft(type: .expense, amount: 10, from: "acc1", to: nil, cat: nil, expected: .missingCategory),
        InvalidDraft(type: .transfer, amount: 10, from: "acc1", to: "acc1", cat: nil, expected: .sameAccounts),
    ])
    func saveTransactionValidation(_ c: InvalidDraft) async {
        let repo = MockTransactionsRepo()
        var d = TransactionDraft(); d.type = c.type; d.amount = c.amount; d.accountId = c.from; d.toAccountId = c.to; d.categoryId = c.cat
        await #expect(throws: c.expected) { _ = try await SaveTransactionUseCase(repo: repo)(d) }
        #expect(repo.created.isEmpty)
    }

    @Test func transferDefaultsToAmount() async throws {
        let repo = MockTransactionsRepo()
        var d = TransactionDraft(); d.type = .transfer; d.amount = 100; d.currency = "usd"; d.toCurrency = "eur"; d.accountId = "acc1"; d.toAccountId = "acc2"; d.exchangeRate = 0.5
        _ = try await SaveTransactionUseCase(repo: repo)(d)
        #expect(repo.created.first?.toAmount == 50)
    }

    @Test func deleteCheckBlocks() async {
        let repo = MockTransactionsRepo()
        repo.deps = .init(hasDependencies: true, blockDeletion: true, wouldCauseNegativeBalance: true, message: "no", affectedCount: 2)
        #expect(await DeleteTransactionUseCase(repo: repo).check(id: 1) == .blocked("no"))
    }

    @Test func restoreSessionOutcomes() async {
        let auth = MockAuthRepo(), settings = MockSettings()
        #expect(await RestoreSessionUseCase(repo: auth, settings: settings)() == .authenticated(Fixtures.user))
        settings.biometricEnabled = true
        #expect(await RestoreSessionUseCase(repo: auth, settings: settings)() == .locked)
        auth.refreshOK = false
        #expect(await RestoreSessionUseCase(repo: auth, settings: settings)() == .unauthenticated)
        #expect(auth.loggedOut)
        auth.hasStoredSession = false
        #expect(await RestoreSessionUseCase(repo: auth, settings: settings)() == .unauthenticated)
    }

    @Test func loginValidatesEmail() async {
        await #expect(throws: ValidationError.invalidEmail) { _ = try await LoginUseCase(repo: MockAuthRepo())(email: "nope", password: "x") }
    }
}

@Suite("Data mapping")
struct MappingTests {
    @Test func transactionTolerantParsing() throws {
        let j = try JSON.parse(Data(#"{"id":"7","amount":"12.5","currency":"c","description":"d","date":"2026-10-01T10:00:00.000Z","type":"bogus","tags":"[\"a\",\"b\"]","isSystemGenerated":1}"#.utf8))
        let t = Mappers.transaction(j)
        #expect(t.id == 7)
        #expect(t.amount == 12.5)
        #expect(t.type == .expense)          // unknown → expense
        #expect(t.tags == ["a", "b"])        // JSON-encoded string list
        #expect(t.isSystemGenerated)
    }

    @Test func transactionBodyForTransfer() {
        var d = TransactionDraft(); d.type = .transfer; d.amount = 10; d.currency = "c1"; d.toCurrency = "c2"
        d.accountId = "a"; d.toAccountId = "b"; d.date = DateCoding.parse("2026-10-05")!
        let b = Mappers.transactionBody(d)
        #expect(b["fromAccountId"] == "a")
        #expect(b["toCurrency"] == "c2")
        #expect(b["date"] == "2026-10-05")
        #expect(b["categoryId"].isNull)
        #expect(b["tags"].isNull)
    }

    @Test func listUnwrapping() throws {
        let nested = try JSON.parse(Data(#"{"data":{"data":[{"id":1}],"pagination":{}}}"#.utf8))
        let flat = try JSON.parse(Data(#"{"data":[{"id":1},{"id":2}]}"#.utf8))
        let named = try JSON.parse(Data(#"{"data":{"positions":[{"symbol":"A"}]}}"#.utf8))
        #expect(Mappers.list(nested).count == 1)
        #expect(Mappers.list(flat).count == 2)
        #expect(Mappers.list(named, keys: "positions").count == 1)
    }

    @Test func countryRateSnakeCase() throws {
        let r = Mappers.countryRate(try JSON.parse(Data(#"{"currency_code":"BOB","buy_rate":"6.9"}"#.utf8)))
        #expect(r.currencyCode == "BOB" && r.buyRate == 6.9)
    }

    @Test func pinHashMatchesKnownVector() {
        // hex(SHA256("1234" + "salt"))
        #expect(PINHasher.hash(pin: "1234", salt: "salt") == "4b3bed8af7b7612e8c1e25f63ba24496f5b16b2df44efb2db7ce3cb24b7e96f7")
        #expect(PINHasher.isValid("1234") && !PINHasher.isValid("12a4") && !PINHasher.isValid("123"))
        let s = MockSettings(); s.setPIN("4321")
        #expect(s.verifyPIN("4321") && !s.verifyPIN("0000"))
    }

    @Test func periodRanges() {
        let now = DateCoding.parse("2026-03-15")!
        let (s, e) = TransactionFilter.Period.previousMonth.range(now: now)!
        #expect(DateCoding.dayString(s) == "2026-02-01")
        #expect(DateCoding.dayString(e) == "2026-02-28")
        #expect(TransactionFilter.Period.all.range(now: now) == nil)
    }
}

@Suite("Exchange rates")
struct ExchangeRateTests {
    @Test func crossRateFromUSDQuotes() {
        let q = ["BOB": 6.96, "EUR": 0.92]
        #expect(ExchangeMath.crossRate(from: "USD", to: "BOB", quotes: q) == 6.96)
        #expect(abs(ExchangeMath.crossRate(from: "BOB", to: "USD", quotes: q)! - 1 / 6.96) < 1e-12)
        #expect(abs(ExchangeMath.crossRate(from: "EUR", to: "BOB", quotes: q)! - 6.96 / 0.92) < 1e-12)
        #expect(ExchangeMath.crossRate(from: "ARS", to: "BOB", quotes: q) == nil)
    }

    @Test func ratesUseCaseDBFirstThenExternalAndSkipsUSD() async {
        let c = MockCatalog()
        c.prefs = [.init(id: "1", currencyId: "u", currencyCode: "USD", isBaseCurrency: true),
                   .init(id: "2", currencyId: "b", currencyCode: "bob", isBaseCurrency: false),
                   .init(id: "3", currencyId: "a", currencyCode: "ARS", isBaseCurrency: false)]
        c.stored = ["BOB": 6.96]
        c.external = ["ARS": 1200, "BOB": 7.1]
        let uc = LoadTransactionRatesUseCase(catalog: c)
        let codes = await uc.currencies()
        #expect(codes == ["BOB", "ARS"])
        let q = await uc(codes)
        #expect(q["BOB"] == RateQuote(code: "BOB", rate: 6.96, source: .database))
        #expect(q["ARS"] == RateQuote(code: "ARS", rate: 1200, source: .external))
        let forced = await uc(codes, forceExternal: true)
        #expect(forced["BOB"]?.rate == 7.1)
    }

    @Test func ratesUseCaseFallbackCurrencies() async {
        #expect(await LoadTransactionRatesUseCase(catalog: MockCatalog()).currencies() == ["BOB", "EUR"])
    }

    @Test func expenseSendsCustomAndManualRates() {
        var d = TransactionDraft(); d.type = .expense; d.amount = 100; d.currency = "cur-bob"; d.currencyCode = "BOB"
        d.accountId = "a"; d.categoryId = "c"; d.manualRates = ["BOB": 9.5, "EUR": 0.9]
        let b = Mappers.transactionBody(d)
        #expect(b["customExchangeRate"] == 9.5)
        #expect(b["manualExchangeRates"]["EUR"] == 0.9)
    }

    @Test func transferNeverSendsCustomRate() {
        var d = TransactionDraft(); d.type = .transfer; d.currencyCode = "BOB"; d.manualRates = ["BOB": 9.5]
        #expect(Mappers.transactionBody(d)["customExchangeRate"].isNull)
        #expect(Mappers.transactionBody(d)["manualExchangeRates"]["BOB"] == 9.5)
    }

    @Test func sameCurrencyTransferUsesTransfersEndpoint() async throws {
        let repo = MockTransactionsRepo()
        var d = TransactionDraft(); d.type = .transfer; d.amount = 50; d.currency = "usd"; d.toCurrency = "usd"
        d.accountId = "a"; d.toAccountId = "b"; d.exchangeRate = 3
        let out = try await SaveTransactionUseCase(repo: repo)(d)
        #expect(out == .transfer)
        #expect(repo.created.isEmpty)
        #expect(repo.transfers.first?.description == "Traspaso")
        #expect(repo.transfers.first?.exchangeRate == nil)
    }

    @Test func currencyExchangeUsesTransactionsEndpoint() async throws {
        let repo = MockTransactionsRepo()
        var d = TransactionDraft(); d.type = .transfer; d.amount = 100; d.currency = "usd"; d.toCurrency = "bob"
        d.accountId = "a"; d.toAccountId = "b"; d.exchangeRate = 6.96
        _ = try await SaveTransactionUseCase(repo: repo)(d)
        #expect(repo.transfers.isEmpty)
        #expect(repo.created.first?.toAmount == 696)
    }

    @Test func fxTargetFromSnapshots() throws {
        let j = try JSON.parse(Data(#"{"id":1,"amount":100,"currency":"u","currencyCode":"USD","description":"","date":"2026-10-01","type":"transfer","toAmount":696,"exchangeRate":6.96,"currencySnapshots":[{"currencyId":"e","currencyCode":"EUR","convertedAmount":92,"exchangeRate":0.92},{"currencyId":"b","currencyCode":"BOB","convertedAmount":696,"exchangeRate":6.96}]}"#.utf8))
        let t = Mappers.transaction(j)
        #expect(t.isCurrencyExchange)
        #expect(t.fxTargetCode == "BOB")
    }

    @Test func localeTolerantParsing() {
        let vm = TransactionFormViewModel(save: SaveTransactionUseCase(repo: MockTransactionsRepo()), catalog: MockCatalog())
        #expect(vm.parse("1.234,5") == 1234.5)
        #expect(vm.parse("1,234.5") == 1234.5)
        #expect(vm.parse("6,96") == 6.96)
        #expect(vm.parse("USD 10") == 10)
        #expect(Fmt.editable(1234.5) .contains(".") == false || Fmt.editable(1234.5) == "1234.5")
    }

    @Test func rateOverrideFlow() async {
        let c = MockCatalog(); c.stored = ["BOB": 6.96]
        let vm = TransactionFormViewModel(save: SaveTransactionUseCase(repo: MockTransactionsRepo()), catalog: c)
        await vm.loadCatalog()
        #expect(vm.rate(for: "BOB") == 6.96)
        vm.beginEditRate("BOB"); vm.rateEditText = "9,5"; vm.applyRateOnce()
        #expect(vm.rate(for: "BOB") == 9.5 && vm.isManual("BOB"))
        vm.beginEditRate("BOB"); vm.rateEditText = "7"; await vm.saveRateGlobally()
        #expect(c.saved.first?.1 == 7)
        #expect(vm.rate(for: "BOB") == 7 && !vm.isManual("BOB"))
    }
}

@Suite("Design review logic")
struct DesignReviewTests {
    @Test func moneyUsesLocalSymbolsAndSpanishGrouping() {
        #expect(Fmt.money(1539) == "$1.539,00")
        #expect(Fmt.money(-70, currency: "USD") == "−$70,00")
        #expect(Fmt.money(100, currency: "BOB") == "Bs 100,00")
        #expect(Fmt.money(92, currency: "EUR") == "€92,00")
        #expect(Fmt.money(5, currency: "XYZ") == "5,00 XYZ")
        #expect(Fmt.money(17_220, compact: true) == "$17,2 mil")
        #expect(Fmt.grouped(1234567.891) == "1.234.567,89")
    }

    @Test func categoryNamesTranslated() {
        #expect(CategoryNames.localized("Healthcare") == "Salud")
        #expect(CategoryNames.localized("Food & Dining") == "Alimentación")
        #expect(CategoryNames.localized("Mi categoría") == "Mi categoría")
        #expect(CategoryNames.localized("x", code: "MARKET") == "Mercado")
    }

    @Test func formCtaAndMissingFields() async {
        let c = MockCatalog(); c.stored = ["BOB": 9.96]
        let vm = TransactionFormViewModel(save: SaveTransactionUseCase(repo: MockTransactionsRepo()), catalog: c)
        await vm.loadCatalog()
        #expect(vm.ctaTitle.hasPrefix("Falta:"))
        vm.amountText = "420"
        vm.draft.accountId = "acc1"   // BOB account
        vm.syncCurrency()
        vm.draft.categoryId = "c-food"
        #expect(vm.ctaTitle == "Guardar gasto · Bs 420,00")
        #expect(vm.showsRateCard)
        #expect(abs((vm.equivalentUSD ?? 0) - 420 / 9.96) < 1e-9)
        #expect(vm.alsoSavedIn.first?.code == "USD")
    }

    @Test func sellEstimatesProfitAndBlocksOverMax() {
        let h = HoldingRow(symbol: "AAPL", quantity: 10, avgPrice: 180, invested: 1800, value: 2290, sector: nil,
                           isStablecoin: false, exchanges: [], operationCount: 1)
        let vm = InvestmentFormViewModel(isCrypto: false, stocks: NoopInvestments(), crypto: NoopCrypto(), holding: h, operation: .sell)
        vm.quantityText = "2"; vm.priceText = "229"; vm.feeText = "1"
        #expect(abs((vm.estimatedProfit ?? 0) - 97) < 1e-9)
        #expect(vm.total == 457)
        vm.quantityText = "11"
        #expect(vm.overMax && !vm.canSubmit)
        vm.draft.operationType = .buy; vm.quantityText = "10"; vm.priceText = "220"
        #expect(vm.newAverage == 200)
    }
}

final class NoopInvestments: InvestmentsRepository {
    func positions() async throws -> [StockPosition] { [] }
    func operations(page: Int) async throws -> Page<Investment> { Page(items: [], pagination: .init()) }
    func pnl() async throws -> [AssetPnL] { [] }
    func pnlSummary() async throws -> PnLSummary { PnLSummary(totalPnL: 0, totalPnLPercent: 0, totalInvested: 0, currentValue: 0, bestPercent: 0, worstPercent: 0) }
    func sales() async throws -> [SaleRecord] { [] }
    func create(_ draft: InvestmentDraft) async throws {}
    func update(id: Int, _ draft: InvestmentDraft) async throws {}
    func delete(id: Int) async throws {}
    func updatePrices() async throws {}
}

final class NoopCrypto: CryptoRepository {
    func portfolio() async throws -> CryptoPortfolio { CryptoPortfolio(totalInvested: 0, currentValue: 0, gainLoss: 0, gainLossPercent: 0, realizedPnL: 0, unrealizedPnL: 0, uniqueSymbols: 0, totalTransactions: 0) }
    func positions() async throws -> [CryptoPosition] { [] }
    func transactions(page: Int) async throws -> Page<CryptoTransaction> { Page(items: [], pagination: .init()) }
    func pnl() async throws -> [AssetPnL] { [] }
    func sales() async throws -> [SaleRecord] { [] }
    func create(_ draft: InvestmentDraft) async throws {}
    func update(id: Int, _ draft: InvestmentDraft) async throws {}
    func delete(id: Int) async throws {}
    func updatePrices() async throws {}
}

@Suite("Google sign-in")
struct GoogleSignInTests {
    @Test func successSendsIDTokenToBackend() async throws {
        let repo = MockAuthRepo(); let google = MockGoogle()
        let user = try await GoogleLoginUseCase(google: google, repo: repo)()
        #expect(user == Fixtures.user)
        #expect(repo.googleToken == "google-id-token")
    }

    @Test func cancelReturnsNilWithoutCallingBackend() async throws {
        let repo = MockAuthRepo(); let google = MockGoogle(); google.result = .success(nil)
        let user = try await GoogleLoginUseCase(google: google, repo: repo)()
        #expect(user == nil)
        #expect(repo.googleToken == nil)
    }

    @Test func failureSurfacesErrorInViewModel() async {
        struct Boom: LocalizedError { var errorDescription: String? { "Google falló" } }
        let repo = MockAuthRepo(); let google = MockGoogle(); google.result = .failure(Boom())
        let vm = LoginViewModel(login: .init(repo: repo), auth: repo, googleLogin: .init(google: google, repo: repo))
        let user = await vm.signInWithGoogle()
        #expect(user == nil)
        #expect(vm.errorMessage == "Google falló")
        #expect(!vm.isGoogleLoading)
    }

    @Test func pkceChallengeIsBase64URLSHA256() {
        // Expected value computed independently: base64url(sha256(verifier)) without padding.
        #expect(GoogleOAuthProvider.challenge(for: "dBjftJeZ4CVP-mB92K1QcQIEp9mZmWZaugpcGcIcVmF") == "zh2JKYKJEdjv_GC0xYVOV8LDeJDt4nRuPM1OkjcvyAc")
        let v = GoogleOAuthProvider.randomURLSafe(bytes: 32)
        #expect(v.count == 43 && !v.contains("+") && !v.contains("/") && !v.contains("="))
    }

    @Test func redirectSchemeIsReversedClientID() {
        let p = GoogleOAuthProvider(clientID: "123-abc.apps.googleusercontent.com")
        #expect(p.redirectScheme == "com.googleusercontent.apps.123-abc")
        #expect(p.redirectURI == "com.googleusercontent.apps.123-abc:/oauth2redirect")
    }
}

@Suite("Bar metrics")
struct BarMetricsTests {
    @Test func barWidthIsClampedAndFinite() {
        #expect(BarMetrics.width(200, 0.5) == 100)
        #expect(BarMetrics.width(200, -0.3) == 0)
        #expect(BarMetrics.width(200, 1.7) == 200)
        #expect(BarMetrics.width(200, .nan) == 0)
        #expect(BarMetrics.width(200, .infinity) == 0)
        #expect(BarMetrics.width(0, 0.5) == 0)
    }
}

@Suite("Adaptive colors")
struct AdaptiveColorTests {
    @Test func resolvesPerAppearanceOffMainThread() async {
        // Regression: providers ran MainActor-isolated and trapped on SwiftUI's render thread.
        let resolved: (CGFloat, CGFloat) = await Task.detached {
            let c = UIColor.adaptive(light: 0x000000, dark: 0xFFFFFF)
            let light = c.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).luminance
            let dark = c.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).luminance
            return (light, dark)
        }.value
        #expect(resolved.0 < 0.01)
        #expect(resolved.1 > 0.99)
    }

    @Test func liftsDarkBackendColorsOnlyInDarkMode() async {
        let (light, dark): (CGFloat, CGFloat) = await Task.detached {
            let c = UIColor.adaptiveLifted(hex: 0x15307C)
            return (c.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).luminance,
                    c.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).luminance)
        }.value
        #expect(dark > light * 3)
    }
}

@Suite("Quantity formatting")
struct QuantityFormatTests {
    @Test func sharesNeverRoundFractionsToWholeNumbers() {
        #expect(Fmt.quantity(0.7, crypto: false) == "0,70")
        #expect(Fmt.quantity(5, crypto: false) == "5")
        #expect(Fmt.quantity(2.3333, crypto: false) == "2,3333")
        #expect(Fmt.quantity(0.0228, crypto: true) == "0,0228")
    }
}
