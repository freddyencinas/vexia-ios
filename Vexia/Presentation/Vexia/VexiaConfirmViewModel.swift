import SwiftUI

/// One-tap confirmation of an AI-captured transaction (design: "Vexia: confirmar").
@Observable
final class VexiaConfirmViewModel {
    var draft: TransactionDraft
    let notes: [String]
    let heard: String
    private(set) var accounts: [Account] = []
    private(set) var categories: [FinancialCategory] = []
    private(set) var isSaving = false
    var errorMessage: String?
    private let save: SaveTransactionUseCase
    private let catalog: CatalogRepository

    init(draft: TransactionDraft, notes: [String], heard: String, save: SaveTransactionUseCase, catalog: CatalogRepository) {
        self.draft = draft; self.notes = notes; self.heard = heard; self.save = save; self.catalog = catalog
    }

    func load() async {
        async let a = try? catalog.accounts()
        async let c = try? catalog.categories(type: nil)
        accounts = await a ?? []
        categories = await c ?? []
        syncCurrency()
    }

    var account: Account? { accounts.first { $0.id == draft.accountId } }
    var category: FinancialCategory? { categories.first { $0.id == draft.categoryId } }
    var typeCategories: [FinancialCategory] { categories.filter { $0.type == draft.type.rawValue } }
    var missing: [String] {
        var m: [String] = []
        if draft.amount <= 0 { m.append(String(localized: "monto")) }
        if account == nil { m.append(String(localized: "cuenta")) }
        if draft.type != .transfer && category == nil { m.append(String(localized: "categoría")) }
        return m
    }
    var amountText: String { Fmt.money(draft.amount, currency: account?.code ?? draft.currencyCode.nilIfEmpty ?? "USD") }

    func syncCurrency() {
        if let a = account { draft.currency = a.currencyId; draft.currencyCode = a.code.uppercased() }
    }

    func confirm() async -> Bool {
        syncCurrency()
        isSaving = true; defer { isSaving = false }
        do { try await save(draft); return true } catch { errorMessage = error.localizedDescription; return false }
    }
}
