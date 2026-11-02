import Foundation

/// How the user actually uses categories and accounts, derived from their own history.
/// Drives the form defaults: most-used categories first, last-used account preselected.
nonisolated struct UsageStats: Codable, Hashable, Sendable {
    struct Use: Codable, Hashable, Sendable {
        var count: Int
        var last: Date
    }
    struct LastAccount: Codable, Hashable, Sendable {
        var id: String
        var at: Date
    }

    /// Transaction type raw value → category id → use.
    private(set) var categories: [String: [String: Use]] = [:]
    /// Account slot ("expense", "income", "transfer", "transfer.to") → last account used there.
    private(set) var accounts: [String: LastAccount] = [:]

    static let transferDestination = "transfer.to"

    static func compute(from transactions: [Transaction]) -> UsageStats {
        var stats = UsageStats()
        for t in transactions where !t.isSystemGenerated {
            let from = t.type == .transfer ? (t.fromAccountId ?? t.accountId) : t.accountId
            stats.record(type: t.type, categoryId: t.categoryId, accountId: from,
                         toAccountId: t.type == .transfer ? t.toAccountId : nil, at: t.date)
        }
        return stats
    }

    mutating func record(type: TransactionType, categoryId: String?, accountId: String?, toAccountId: String?, at date: Date) {
        if let c = categoryId, type != .transfer {
            var use = categories[type.rawValue, default: [:]][c] ?? Use(count: 0, last: date)
            use.count += 1
            use.last = max(use.last, date)
            categories[type.rawValue, default: [:]][c] = use
        }
        func mark(_ slot: String, _ id: String?) {
            guard let id else { return }
            if let current = accounts[slot], current.at > date { return }
            accounts[slot] = LastAccount(id: id, at: date)
        }
        mark(type.rawValue, accountId)
        if type == .transfer { mark(Self.transferDestination, toAccountId) }
    }

    /// Category ids of `type`, most used first (ties → most recent).
    func rankedCategoryIds(for type: TransactionType) -> [String] {
        let uses: [String: Use] = categories[type.rawValue] ?? [:]
        let ordered = uses.sorted { (a: (key: String, value: Use), b: (key: String, value: Use)) -> Bool in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            return a.value.last > b.value.last
        }
        return ordered.map { $0.key }
    }

    func lastAccountId(for type: TransactionType) -> String? { accounts[type.rawValue]?.id }
    var lastTransferDestinationId: String? { accounts[Self.transferDestination]?.id }
}
