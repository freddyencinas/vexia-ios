import SwiftUI

/// One-tap confirmation of an AI-captured transaction (design: "Vexia: confirmar").
@Observable
final class VexiaConfirmViewModel {
    var draft: TransactionDraft
    let notes: [String]
    let heard: String
    /// Read from a receipt: nothing was heard, and "retry" means scanning again.
    let fromReceipt: Bool
    private(set) var accounts: [Account] = []
    private(set) var categories: [FinancialCategory] = []
    private(set) var isSaving = false
    var errorMessage: String?
    private let save: SaveTransactionUseCase
    private let catalog: CatalogRepository

    init(draft: TransactionDraft, notes: [String], heard: String, fromReceipt: Bool = false,
         save: SaveTransactionUseCase, catalog: CatalogRepository) {
        self.draft = draft; self.notes = notes; self.heard = heard; self.fromReceipt = fromReceipt
        self.save = save; self.catalog = catalog
    }

    var showsHeard: Bool { !fromReceipt && !heard.trimmingCharacters(in: .whitespaces).isEmpty }

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
    /// Editable text in the keyboard's decimal separator; empty when the AI found no amount.
    var amountEditText: String {
        draft.amount > 0 ? draft.amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) : ""
    }

    /// The AI misreads amounts (receipt totals, spoken numbers): the user fixes them here.
    func setAmount(_ text: String) {
        guard let value = AmountMath.parse(text).map({ NSDecimalNumber(decimal: $0).doubleValue }), value > 0 else { return }
        if draft.toAmount == draft.amount { draft.toAmount = value }   // same-currency transfer mirrors the amount
        draft.amount = value
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
