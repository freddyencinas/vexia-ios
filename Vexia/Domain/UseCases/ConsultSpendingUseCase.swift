import Foundation

/// Spoken-question periods ("¿cuánto gasté esta semana?").
nonisolated enum SpendingPeriod: String, CaseIterable, Sendable {
    case today, thisWeek, thisMonth, lastMonth

    /// First and last day, both inclusive (the API takes day strings).
    func days(now: Date = .now, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return (today, today)
        case .thisWeek:
            return (calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today, today)
        case .thisMonth:
            return (calendar.dateInterval(of: .month, for: now)?.start ?? today, today)
        case .lastMonth:
            let start = calendar.date(byAdding: .month, value: -1, to: calendar.dateInterval(of: .month, for: now)?.start ?? today) ?? today
            return (start, calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start)
        }
    }
}

/// Expenses of a period, optionally of one category, in the user's base currency.
/// Uses the same spending analysis as the dashboard, so Siri and Inicio never disagree.
struct ConsultSpendingUseCase {
    let dashboard: DashboardRepository
    let catalog: CatalogRepository

    nonisolated struct Report: Equatable, Sendable {
        var period: SpendingPeriod
        var currency: String
        var total: Double
        var count: Int
        /// Requested category; nil = all expenses.
        var category: SpendingAnalysis.Category?
        var categoryName: String?
        /// Largest categories (all expenses) or largest expenses of the category.
        var topCategories: [SpendingAnalysis.Category]
        var topExpenses: [SpendingAnalysis.TopExpense]
    }

    func callAsFunction(period: SpendingPeriod, categoryId: String? = nil, categoryName: String? = nil,
                        now: Date = .now) async throws -> Report {
        let days = period.days(now: now)
        async let spending = dashboard.spending(start: days.start, end: days.end)
        async let prefs = try? catalog.currencyPreferences()
        let s = try await spending
        let currency = await prefs?.first(where: \.isBaseCurrency)?.currencyCode.uppercased() ?? "USD"
        return Self.report(s, period: period, currency: currency, categoryId: categoryId, categoryName: categoryName)
    }

    nonisolated static func report(_ s: SpendingAnalysis, period: SpendingPeriod, currency: String,
                                   categoryId: String?, categoryName: String?) -> Report {
        let sorted = s.categories.filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
        guard let categoryId else {
            return Report(period: period, currency: currency, total: s.totalSpent, count: sorted.reduce(0) { $0 + $1.transactionCount },
                          category: nil, categoryName: nil, topCategories: Array(sorted.prefix(3)), topExpenses: [])
        }
        let match = s.categories.first { $0.categoryId == categoryId }
        let name = match?.categoryName ?? categoryName
        return Report(period: period, currency: currency, total: match?.amount ?? 0, count: match?.transactionCount ?? 0,
                      category: match, categoryName: name, topCategories: [],
                      topExpenses: Array(s.topExpenses.filter { $0.categoryName == name }.prefix(3)))
    }
}
