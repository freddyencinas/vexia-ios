import Foundation

nonisolated enum TransactionType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case income, expense, transfer
    var id: String { rawValue }
    var title: String {
        switch self { case .income: String(localized: "Ingreso"); case .expense: String(localized: "Gasto"); case .transfer: String(localized: "Transferencia") }
    }
}

nonisolated struct CurrencySnapshot: Hashable, Sendable {
    var currencyId: String
    var currencyCode: String
    var convertedAmount: Double
    var exchangeRate: Double
}

nonisolated struct Transaction: Identifiable, Hashable, Sendable {
    let id: Int
    var amount: Double
    var currency: String
    var currencyCode: String?
    var description: String
    var date: Date
    var categoryId: String?
    var categoryName: String?
    var categoryIcon: String?
    var tags: [String]
    var type: TransactionType
    var isRecurring: Bool
    var isSystemGenerated: Bool
    var usdAmount: Double?
    var accountId: String?
    var accountName: String?
    var fromAccountId: String?
    var toAccountId: String?
    var fromAccountName: String?
    var toAccountName: String?
    var fromAmount: Double?
    var toAmount: Double?
    var exchangeRate: Double?
    var currencySnapshots: [CurrencySnapshot]

    var displayCurrency: String { currencyCode ?? currency }

    /// Currency exchange = transfer with a rate between different currencies.
    var isCurrencyExchange: Bool { type == .transfer && (exchangeRate ?? 1) != 1 && toAmount != nil }

    /// Target currency of an FX transfer, inferred from snapshots
    var fxTargetCode: String? {
        let from = displayCurrency.uppercased()
        let others = currencySnapshots.filter { $0.currencyCode.uppercased() != from }
        if let target = toAmount.map(abs), target > 0,
           let best = others.min(by: { abs(abs($0.convertedAmount) - target) < abs(abs($1.convertedAmount) - target) }),
           abs(abs(best.convertedAmount) - target) < target * 0.01 {
            return best.currencyCode.uppercased()
        }
        return others.first?.currencyCode.uppercased()
    }
    var isIncome: Bool { type == .income }
}

nonisolated struct Pagination: Hashable, Sendable {
    var page = 1, limit = 20, total = 0, totalPages = 1
    var hasNext = false
}

nonisolated struct Page<T: Sendable & Hashable>: Hashable, Sendable {
    var items: [T]
    var pagination: Pagination
}

nonisolated struct TransactionFilter: Hashable, Sendable {
    enum Period: String, CaseIterable, Identifiable, Sendable {
        case currentMonth, previousMonth, all
        var id: String { rawValue }
        func range(now: Date = .now, calendar: Calendar = .current) -> (Date, Date)? {
            switch self {
            case .all: return nil
            case .currentMonth:
                let start = calendar.dateInterval(of: .month, for: now)!.start
                let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
                return (start, end)
            case .previousMonth:
                let prev = calendar.date(byAdding: .month, value: -1, to: now)!
                let start = calendar.dateInterval(of: .month, for: prev)!.start
                let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
                return (start, end)
            }
        }
    }
    var type: TransactionType?
    var period: Period = .currentMonth
    /// When set, overrides `period` with that calendar month.
    var monthStart: Date?

    func dateRange(calendar: Calendar = .current) -> (Date, Date)? {
        if let m = monthStart {
            let start = calendar.dateInterval(of: .month, for: m)!.start
            return (start, calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!)
        }
        return period.range(calendar: calendar)
    }
    var categoryId: String?
    var accountId: String?
    var search: String = ""
}

/// Draft used by create/edit form.
nonisolated struct TransactionDraft: Hashable, Sendable {
    var type: TransactionType = .expense
    var amount: Double = 0
    var currency: String = ""
    var description: String = ""
    var date: Date = .now
    var accountId: String?
    var categoryId: String?
    var tags: [String] = []
    var isRecurring = false
    var recurringFrequency: RecurringFrequency = .monthly
    // transfer
    var toAccountId: String?
    var toCurrency: String = ""
    var toAmount: Double = 0
    var exchangeRate: Double?
    // FX: per-transaction manual rates
    /// ISO code of the source account currency (e.g. "BOB"); `currency` holds its id.
    var currencyCode: String = ""
    var toCurrencyCode: String = ""
    /// Per-transaction manual rates, USD→CODE ("Solo esta vez"). Sent as `manualExchangeRates`.
    var manualRates: [String: Double] = [:]

    /// Manual rate for the account currency → backend `customExchangeRate` (income/expense only).
    var customExchangeRate: Double? { type == .transfer ? nil : manualRates[currencyCode.uppercased()] }
    /// Same-currency transfer → `/transfers`; cross-currency → `/transactions` (currency exchange).
    var isCurrencyExchange: Bool { type == .transfer && !toCurrency.isEmpty && toCurrency != currency }

    enum RecurringFrequency: String, CaseIterable, Identifiable, Sendable {
        case daily, weekly, monthly, yearly
        var id: String { rawValue }
        var title: String { switch self { case .daily: String(localized: "Diario"); case .weekly: String(localized: "Semanal"); case .monthly: String(localized: "Mensual"); case .yearly: String(localized: "Anual") } }
    }
}

nonisolated struct TransactionSummary: Hashable, Sendable {
    var totalIncome: Double
    var totalExpenses: Double
    var netAmount: Double
    var transactionCount: Int
    var currencyCode: String?
}

nonisolated struct TransactionDependencies: Hashable, Sendable {
    var hasDependencies: Bool
    var blockDeletion: Bool
    var wouldCauseNegativeBalance: Bool
    var message: String
    var affectedCount: Int
}

nonisolated struct FinancialCategory: Identifiable, Hashable, Sendable {
    let id: String
    var code: String
    var name: String
    var icon: String?
    var type: String // income | expense
    var isGlobal: Bool
}

nonisolated enum AccountType: String, CaseIterable, Sendable {
    case bank, checking, savings, creditCard = "credit_card", cash, investment, crypto, other
    var symbol: String {
        switch self {
        case .bank, .checking: "building.columns"; case .savings: "banknote"; case .creditCard: "creditcard"
        case .cash: "dollarsign.circle"; case .investment: "chart.line.uptrend.xyaxis"; case .crypto: "bitcoinsign.circle"
        case .other: "wallet.bifold"
        }
    }
}

nonisolated struct Account: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var type: AccountType
    var currencyId: String
    var currencyCode: String?
    var initialBalance: Double
    var currentBalance: Double?
    var color: String?
    var isFavorite: Bool

    var balance: Double { currentBalance ?? initialBalance }
    var code: String { currencyCode ?? currencyId }
}

nonisolated struct CurrencyPreference: Identifiable, Hashable, Sendable {
    let id: String
    var currencyId: String
    var currencyCode: String
    var currencySymbol: String?
    var isBaseCurrency: Bool
}

/// USD-based quote for one currency (1 USD = `rate` CODE), same convention as the backend.
nonisolated struct RateQuote: Hashable, Sendable {
    enum Source: String, Sendable { case database, external, manual, snapshot, saved }
    var code: String
    var rate: Double
    var source: Source
}

nonisolated enum ExchangeMath {
    /// Rate to convert 1 unit of `from` into `to`, given USD→X quotes (USD itself = 1).
    static func crossRate(from: String, to: String, quotes: [String: Double]) -> Double? {
        func usd(_ c: String) -> Double? { c.uppercased() == "USD" ? 1 : quotes[c.uppercased()] }
        guard let f = usd(from), let t = usd(to), f > 0 else { return nil }
        return t / f
    }
}

nonisolated struct CountryRate: Identifiable, Hashable, Sendable {
    var id: String
    var currencyCode: String
    var currencyName: String
    var country: String
    var buyRate: Double
    var sellRate: Double
    var officialRate: Double
    var source: String
    var updatedAt: Date?
}
