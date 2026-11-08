import Foundation

/// Turns free text (voice transcript) or a receipt image into a structured transaction proposal.
/// Depends ONLY on ports:
/// any LLM SDK can be plugged in through `LLMProvider`.
struct ClassifyTransactionUseCase {
    static let promptId = "ExpenseIncomeClassifier"
    static let receiptPrompt = "Revisa este comprobante y extrae la transacción."

    let llm: LLMProvider
    let prompts: PromptRepository
    var receiptReader: ReceiptTextReader? = nil

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
        guard let imageJPEG else {
            let raw = try await llm.infer(prompt: input, system: system)
            return Self.postProcess(try VexiaResultParser.parse(raw), accounts: accounts, categories: categories, transcript: input)
        }
        // OCR text goes to the model (exact digits) and decides account/currency (models skip them).
        let ocr = ((try? await receiptReader?.text(in: imageJPEG)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = Self.receiptPrompt(input.isEmpty ? Self.receiptPrompt : input, ocr: ocr)
        let raw = try await llm.infer(prompt: prompt, system: system, imageJPEG: imageJPEG)
        var r = Self.postProcess(try VexiaResultParser.parse(raw), accounts: accounts, categories: categories, transcript: input)
        if !ocr.isEmpty { r = Self.applyReceiptText(ocr, to: r, accounts: accounts) }
        return r
    }

    nonisolated static func receiptPrompt(_ prompt: String, ocr: String) -> String {
        ocr.isEmpty ? prompt : prompt + "\n\nTexto del comprobante (OCR):\n" + ocr
    }

    /// A bank printed on the receipt beats the model's guess; so does its currency ("Bs 400.00").
    nonisolated static func applyReceiptText(_ ocr: String, to r: VexiaResult, accounts: [Account]) -> VexiaResult {
        var r = r
        if r.form.type != TransactionType.transfer.rawValue, let a = AccountMatcher.mentioned(in: ocr, accounts: accounts) {
            r.form.accountFromId = a.id
        }
        if let c = AccountMatcher.spokenCurrency(in: ocr) { r.form.currency = c }
        return r
    }

    nonisolated static func lines(_ cats: [FinancialCategory]) -> String {
        cats.map { "- \($0.code): \($0.name)" }.joined(separator: "\n")
    }

    /// Account names/ids not belonging to the user are dropped; category codes resolved to ids.
    /// The LLM (especially on-device) often paraphrases account names ("BCP" for "Banco BCP Bs") or
    /// omits them, so names are matched loosely and the transcript itself is the last resort.
    nonisolated static func postProcess(_ r: VexiaResult, accounts: [Account], categories: [FinancialCategory],
                                        transcript: String? = nil) -> VexiaResult {
        var r = r
        func resolveAccount(_ v: String?) -> String? {
            guard let v else { return nil }
            return (accounts.first { $0.id == v } ?? AccountMatcher.match(v, in: accounts))?.id
        }
        r.form.accountFromId = resolveAccount(r.form.accountFromId)
        r.form.accountToId = resolveAccount(r.form.accountToId)
        if let transcript, !transcript.isEmpty {
            // Small models copy prompt examples ("Banco BCP", "salteña"): keep only what was actually said.
            if let id = r.form.accountFromId, let a = accounts.first(where: { $0.id == id }), !Grounding.said(a.name, in: transcript) {
                r.form.accountFromId = nil
            }
            if let d = r.form.description, !Grounding.said(d, in: transcript) {
                r.form.description = r.form.merchantOrPayee.flatMap { Grounding.said($0, in: transcript) ? $0 : nil }
            }
            if r.form.accountFromId == nil, r.form.type != TransactionType.transfer.rawValue {
                r.form.accountFromId = AccountMatcher.mentioned(in: transcript, accounts: accounts)?.id
            }
            if r.form.currency == nil { r.form.currency = AccountMatcher.spokenCurrency(in: transcript) }
        }
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
    /// Account priority: named by the user → last used in the spoken currency → any in that currency
    /// → last used for this type → favorite → first.
    nonisolated static func draft(from r: VexiaResult, accounts: [Account], usage: UsageStats? = nil) -> TransactionDraft {
        var d = TransactionDraft()
        d.type = TransactionType(rawValue: r.form.type ?? r.intent.rawValue) ?? .expense
        d.amount = r.form.amount ?? 0
        d.description = r.form.description ?? r.form.merchantOrPayee ?? ""
        d.date = r.form.resolvedDate()
        d.categoryId = r.form.categoryId
        // Spoken currency wins over list order ("35 dólares" must not land in a Bs account).
        let spoken = r.form.currency?.uppercased()
        let sameCurrency = accounts.filter { spoken != nil && $0.code.uppercased() == Self.isoCode(spoken!) }
        let lastUsed = accounts.first { $0.id == usage?.lastAccountId(for: d.type) }
        let lastUsedInCurrency: Account? = lastUsed.flatMap { sameCurrency.contains($0) ? $0 : nil }
        let candidates: [String?] = [
            r.form.accountFromId,
            lastUsedInCurrency?.id,
            sameCurrency.first(where: \.isFavorite)?.id, sameCurrency.first?.id,
            lastUsed?.id,
            accounts.first(where: \.isFavorite)?.id, accounts.first?.id,
        ]
        d.accountId = candidates.compactMap { $0 }.first
        d.toAccountId = r.form.accountToId
        d.tags = r.form.tags
        let account = accounts.first { $0.id == d.accountId }
        d.currency = account?.currencyId ?? ""
        d.currencyCode = account?.code.uppercased() ?? ""
        return d
    }
}

/// Whether a value returned by the LLM appears in what the user said (accents, case and plurals ignored).
nonisolated enum Grounding {
    static func said(_ value: String, in transcript: String) -> Bool {
        let heard = AccountMatcher.tokens(transcript)
        let words = AccountMatcher.tokens(value).filter { $0.count >= 3 }
        guard !words.isEmpty else { return true }   // nothing identifying to check ("BCP" → "bcp" still counts)
        let found = words.filter { w in heard.contains { $0 == w || ($0.count >= 4 && w.count >= 4 && ($0.hasPrefix(w) || w.hasPrefix($0))) } }
        return found.count * 2 >= words.count
    }
}

/// Loose account-name matching for AI results and raw transcripts.
nonisolated enum AccountMatcher {
    /// Words that don't identify an account ("banco BCP", "cuenta de ahorro").
    private static let filler: Set<String> = ["banco", "bank", "cuenta", "account", "de", "del", "la", "el", "mi", "my", "con", "en", "with"]

    static func tokens(_ s: String) -> [String] {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !filler.contains($0) }
    }

    /// Name returned by the LLM → account: exact (normalized) first, then one name's words contained in the other's.
    static func match(_ name: String, in accounts: [Account]) -> Account? {
        let q = tokens(name)
        guard !q.isEmpty else { return nil }
        if let exact = accounts.first(where: { tokens($0.name) == q }) { return exact }
        let candidates = accounts.filter { a in
            let t = tokens(a.name)
            return !t.isEmpty && (Set(q).isSubset(of: t) || Set(t).isSubset(of: q))
        }
        return candidates.count == 1 ? candidates[0] : nil  // ambiguous → let the user pick
    }

    /// Currency words name many accounts ("BCP Bolivianos", "Efectivo Bs"), so they never identify one.
    private static let currencyWords: Set<String> = ["bs", "bob", "bolivianos", "boliviano", "usd", "dolares", "dolar", "dollars", "dollar", "eur", "euros"]

    /// Account sharing the most identifying words with what the user said; ties → nil (user picks).
    static func mentioned(in transcript: String, accounts: [Account]) -> Account? {
        let said = Set(tokens(transcript)).subtracting(currencyWords)
        let hits = accounts.compactMap { a -> (Account, Int)? in
            let n = Set(tokens(a.name)).subtracting(currencyWords).intersection(said).count
            return n > 0 ? (a, n) : nil
        }
        guard let best = hits.max(by: { $0.1 < $1.1 }), hits.filter({ $0.1 == best.1 }).count == 1 else { return nil }
        return best.0
    }

    static func spokenCurrency(in transcript: String) -> String? {
        let said = Set(tokens(transcript))
        if !said.isDisjoint(with: ["bs", "bolivianos", "boliviano", "bob"]) { return "BOB" }
        if !said.isDisjoint(with: ["dolares", "dolar", "dollars", "dollar", "usd"]) || transcript.contains("$") { return "USD" }
        return nil
    }
}
