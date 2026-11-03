import Foundation

/// Free text ("50 Bs almuerzo en efectivo") → transaction ready to confirm, for entry points
/// without a form (Siri, Shortcuts). Reuses the same classifier as voice capture.
struct ProposeTransactionUseCase {
    let classify: ClassifyTransactionUseCase
    let catalog: CatalogRepository
    var usage: UsageStats? = nil
    let language: String

    nonisolated enum Missing: Equatable, Sendable { case amount, account, destination, category }

    nonisolated struct Proposal: Equatable, Sendable {
        var draft: TransactionDraft
        var account: Account?
        var destination: Account?
        var category: FinancialCategory?
        /// The text described a question or nothing usable, not a movement to save.
        var isTransaction: Bool
        var missing: [Missing]
        var notes: [String]
        var heard: String
    }

    func callAsFunction(_ text: String) async throws -> Proposal {
        async let a = catalog.accounts()
        async let c = catalog.categories(type: nil)
        let (accounts, categories) = try await (a, c)
        let result = try await classify(text: text, language: language, categories: categories, accounts: accounts)
        let draft = ClassifyTransactionUseCase.draft(from: result, accounts: accounts, usage: usage)
        return Self.proposal(result: result, draft: draft, accounts: accounts, categories: categories, heard: text)
    }

    nonisolated static func proposal(result: VexiaResult, draft: TransactionDraft, accounts: [Account],
                                     categories: [FinancialCategory], heard: String) -> Proposal {
        let account = accounts.first { $0.id == draft.accountId }
        let destination = accounts.first { $0.id == draft.toAccountId }
        let category = categories.first { $0.id == draft.categoryId && $0.type == draft.type.rawValue }
        var missing: [Missing] = []
        if draft.amount <= 0 { missing.append(.amount) }
        if account == nil { missing.append(.account) }
        if draft.type == .transfer {
            if destination == nil || destination == account { missing.append(.destination) }
        } else if category == nil {
            missing.append(.category)
        }
        return Proposal(draft: draft, account: account, destination: destination, category: category,
                        isTransaction: [.expense, .income, .transfer].contains(result.intent) || draft.amount > 0,
                        missing: missing,
                        notes: result.clarifyingQuestions.map(\.question) + result.warnings,
                        heard: heard)
    }
}
