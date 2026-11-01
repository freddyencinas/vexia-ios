import Foundation

nonisolated struct DashboardOverview: Hashable, Sendable {
    struct CurrencyBreakdown: Hashable, Sendable, Identifiable {
        var id: String { currencyId }
        var currencyId: String
        var currencyCode: String
        var amount: Double
        var convertedAmount: Double
    }
    var totalBalance: Double
    var cashBalance: Double
    var investmentsBalance: Double
    var cryptoBalance: Double
    var currencyCode: String
    var breakdown: [CurrencyBreakdown]
    var balanceChange: Double
    var balanceChangePercent: Double
    var savingsRate: Double
    var monthlyIncome: Double
    var monthlyExpenses: Double
    var averageDailyExpense: Double
}

nonisolated struct CashFlow: Hashable, Sendable {
    struct Point: Hashable, Sendable, Identifiable {
        var id: String { period }
        var period: String // YYYY-MM
        var income: Double
        var expenses: Double
        var netFlow: Double
        var date: Date { DateCoding.parse(period + "-01") ?? .now }
    }
    var points: [Point]
    var totalIncome: Double
    var totalExpenses: Double
    var netFlow: Double
}

nonisolated struct SpendingAnalysis: Hashable, Sendable {
    struct Category: Hashable, Sendable, Identifiable {
        var id: String { categoryId }
        var categoryId: String
        var categoryCode: String
        var categoryName: String
        var amount: Double
        var percentage: Double
        var transactionCount: Int
    }
    struct TopExpense: Hashable, Sendable, Identifiable {
        var id: String
        var description: String
        var amount: Double
        var categoryName: String
        var date: Date?
    }
    var totalSpent: Double
    var categories: [Category]
    var topExpenses: [TopExpense]
    var changePercent: Double
}

nonisolated struct PortfolioPerformance: Hashable, Sendable {
    struct Bucket: Hashable, Sendable {
        var totalValue: Double
        var totalInvested: Double
        var totalGain: Double
        var totalGainPercent: Double
        var assets: [Asset]
    }
    struct Asset: Hashable, Sendable, Identifiable {
        var id: String { symbol }
        var symbol: String
        var name: String?
        var currentValue: Double
        var unrealizedGain: Double
        var unrealizedGainPercent: Double
    }
    var investments: Bucket
    var crypto: Bucket
    var combinedValue: Double
    var combinedGain: Double
    var combinedGainPercent: Double
}

nonisolated struct DashboardData: Hashable, Sendable {
    var overview: DashboardOverview?
    var cashFlow: CashFlow?
    var spending: SpendingAnalysis?
    var performance: PortfolioPerformance?
}
