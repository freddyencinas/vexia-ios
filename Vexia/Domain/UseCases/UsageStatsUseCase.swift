import Foundation

/// Local persistence for `UsageStats` so the form opens with the right defaults before the network answers.
protocol UsageStatsStore: AnyObject, Sendable {
    func load() -> UsageStats?
    func save(_ stats: UsageStats)
}

/// Recomputes usage from the latest transactions (no dedicated backend endpoint) and bumps it on every save.
final class UsageStatsUseCase {
    static let sampleSize = 100

    private let repo: TransactionsRepository
    private let store: UsageStatsStore

    init(repo: TransactionsRepository, store: UsageStatsStore) { self.repo = repo; self.store = store }

    var cached: UsageStats { store.load() ?? UsageStats() }

    /// Latest history wins; on failure keeps the cached stats (offline-friendly).
    func refresh() async -> UsageStats {
        guard let page = try? await repo.list(filter: TransactionFilter(period: .all), page: 1, limit: Self.sampleSize) else {
            return cached
        }
        let stats = UsageStats.compute(from: page.items)
        store.save(stats)
        return stats
    }

    /// Called after a successful save so the next form already reflects it.
    func record(_ draft: TransactionDraft) {
        var stats = cached
        stats.record(type: draft.type, categoryId: draft.categoryId, accountId: draft.accountId,
                     toAccountId: draft.type == .transfer ? draft.toAccountId : nil, at: .now)
        store.save(stats)
    }
}
