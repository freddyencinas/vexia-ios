import Foundation

/// Validates and persists a transaction draft.
struct SaveTransactionUseCase {
    let repo: TransactionsRepository

    func validate(_ d: TransactionDraft) throws {
        guard d.amount > 0 else { throw ValidationError.invalidAmount }
        guard d.accountId != nil else { throw ValidationError.missingAccount }
        if d.type == .transfer {
            guard let to = d.toAccountId else { throw ValidationError.missingAccount }
            guard to != d.accountId else { throw ValidationError.sameAccounts }
        } else {
            guard d.categoryId != nil else { throw ValidationError.missingCategory }
        }
    }

    enum Outcome: Equatable { case transaction(Transaction), transfer }

    /// Routing:
    /// same-currency transfer → /transfers, currency exchange & income/expense → /transactions.
    @discardableResult
    func callAsFunction(_ draft: TransactionDraft, editingId: Int? = nil) async throws -> Outcome {
        var d = draft
        d.description = d.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.type == .transfer {
            if !d.isCurrencyExchange { d.exchangeRate = nil; d.toAmount = d.amount }
            else if d.toAmount <= 0 { d.toAmount = d.amount * (d.exchangeRate ?? 1) }
        }
        try validate(d)
        if let editingId { return .transaction(try await repo.update(id: editingId, d)) }
        if d.type == .transfer && !d.isCurrencyExchange {
            if d.description.isEmpty { d.description = "Traspaso" }
            try await repo.createTransfer(d)
            return .transfer
        }
        return .transaction(try await repo.create(d))
    }
}

/// Checks dependencies before deleting.
struct DeleteTransactionUseCase {
    enum Check: Equatable { case safe, warn(String), blocked(String) }
    let repo: TransactionsRepository

    func check(id: Int) async -> Check {
        guard let deps = try? await repo.dependencies(id: id) else { return .safe }
        if deps.blockDeletion { return .blocked(deps.message) }
        if deps.hasDependencies || deps.wouldCauseNegativeBalance { return .warn(deps.message) }
        return .safe
    }

    func callAsFunction(id: Int) async throws { try await repo.delete(id: id) }
}

/// Loads the transaction rates strip:
/// non-USD currencies from user preferences; DB rate first, external provider as fallback.
struct LoadTransactionRatesUseCase {
    let catalog: CatalogRepository
    static let fallbackCurrencies = ["BOB", "EUR"]

    func currencies() async -> [String] {
        let prefs = (try? await catalog.currencyPreferences()) ?? []
        let codes = prefs.map { $0.currencyCode.uppercased() }.filter { $0 != "USD" }
        var seen = Set<String>()
        let unique = codes.filter { seen.insert($0).inserted }
        return unique.isEmpty ? Self.fallbackCurrencies : unique
    }

    func callAsFunction(_ codes: [String], forceExternal: Bool = false) async -> [String: RateQuote] {
        await withTaskGroup(of: RateQuote?.self) { group in
            for code in codes where code != "USD" {
                group.addTask {
                    if !forceExternal, let r = try? await catalog.storedUSDRate(code: code), r > 0 { return RateQuote(code: code, rate: r, source: .database) }
                    if let r = try? await catalog.externalUSDRate(code: code), r > 0 { return RateQuote(code: code, rate: r, source: .external) }
                    return nil
                }
            }
            var out: [String: RateQuote] = [:]
            for await q in group { if let q { out[q.code] = q } }
            return out
        }
    }
}

/// Groups transactions by day for sectioned lists.
nonisolated enum TransactionGrouping {
    static func byDay(_ items: [Transaction], calendar: Calendar = .current) -> [(day: Date, items: [Transaction])] {
        let groups = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.date > $1.date }) }
    }
}
