import Foundation

/// Turns free text (voice transcript) or a receipt image into a structured transaction proposal.
/// Depends ONLY on ports:
/// any LLM SDK can be plugged in through `LLMProvider`.
struct ClassifyTransactionUseCase {
    static let promptId = "ExpenseIncomeClassifier"
    static let receiptPrompt = "Revisa este comprobante y extrae la transacción."

    let llm: LLMProvider
    let prompts: PromptRepository

    func callAsFunction(text: String? = nil, imageJPEG: Data? = nil, language: String,
                        categories: [FinancialCategory], accounts: [Account]) async throws -> VexiaResult {
        let input = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty || imageJPEG != nil else { throw AIError.emptyTranscript }

        let template = try await prompts.prompt(id: Self.promptId, language: language)
        let system = template.systemPrompt(
            expenseCategories: Self.lines(categories.filter { $0.type == "expense" }),
            incomeCategories: Self.lines(categories.filter { $0.type == "income" }),
            accounts: accounts.map { "- \($0.name)" }.joined(separator: "\n")
        )
        let raw: String
        if let imageJPEG {
            raw = try await llm.infer(prompt: input.isEmpty ? Self.receiptPrompt : input, system: system, imageJPEG: imageJPEG)
        } else {
            raw = try await llm.infer(prompt: input, system: system)
        }
        return Self.postProcess(try VexiaResultParser.parse(raw), accounts: accounts, categories: categories)
    }

    nonisolated static func lines(_ cats: [FinancialCategory]) -> String {
        cats.map { "- \($0.code): \($0.name)" }.joined(separator: "\n")
    }

    /// Account names/ids not belonging to the user are dropped; category codes resolved to ids.
    nonisolated static func postProcess(_ r: VexiaResult, accounts: [Account], categories: [FinancialCategory]) -> VexiaResult {
        var r = r
        func resolveAccount(_ v: String?) -> String? {
            guard let v else { return nil }
            return accounts.first { $0.id == v || $0.name.caseInsensitiveCompare(v) == .orderedSame }?.id
        }
        r.form.accountFromId = resolveAccount(r.form.accountFromId)
        r.form.accountToId = resolveAccount(r.form.accountToId)
        if let c = r.form.categoryId {
            r.form.categoryId = categories.first { $0.id == c || $0.code.caseInsensitiveCompare(c) == .orderedSame }?.id
        }
        return r
    }

    /// LLMs may answer "dólares", "$", "bs"… normalize to ISO-ish codes used by accounts.
    nonisolated static func isoCode(_ raw: String) -> String {
        switch raw.uppercased() {
        case "$", "US$", "DOLAR", "DÓLAR", "DOLARES", "DÓLARES", "DOLLAR", "DOLLARS", "USD": "USD"
        case "BS", "BS.", "BOLIVIANOS", "BOLIVIANO", "BOB": "BOB"
        case "€", "EURO", "EUROS", "EUR": "EUR"
        default: raw.uppercased()
        }
    }

    /// Maps the AI result to a form draft (prefill).
    nonisolated static func draft(from r: VexiaResult, accounts: [Account]) -> TransactionDraft {
        var d = TransactionDraft()
        d.type = TransactionType(rawValue: r.form.type ?? r.intent.rawValue) ?? .expense
        d.amount = r.form.amount ?? 0
        d.description = r.form.description ?? r.form.merchantOrPayee ?? ""
        d.date = r.form.resolvedDate()
        d.categoryId = r.form.categoryId
        // Spoken currency wins over list order ("35 dólares" must not land in a Bs account).
        let spoken = r.form.currency?.uppercased()
        let sameCurrency = accounts.filter { spoken != nil && $0.code.uppercased() == Self.isoCode(spoken!) }
        d.accountId = r.form.accountFromId
            ?? sameCurrency.first(where: \.isFavorite)?.id ?? sameCurrency.first?.id
            ?? accounts.first(where: \.isFavorite)?.id ?? accounts.first?.id
        d.toAccountId = r.form.accountToId
        d.tags = r.form.tags
        let account = accounts.first { $0.id == d.accountId }
        d.currency = account?.currencyId ?? ""
        d.currencyCode = account?.code.uppercased() ?? ""
        return d
    }
}
