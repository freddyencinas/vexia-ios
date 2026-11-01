import SwiftUI

@Observable
final class DashboardViewModel {
    /// Balance shown in the hero. Never a fake zero (design review P0).
    enum BalanceState: Equatable {
        case loading
        case live(Double, currency: String)
        case derived(Double, currency: String)               // overview failed → sum of accounts
        case cached(Double, currency: String, at: Date)       // offline → last good value
        case unavailable
    }

    struct MonthTotals: Equatable { var label: String; var income: Double; var expenses: Double; var currency: String
        var net: Double { income - expenses }
        var savingsRate: Double { income > 0 ? net / income * 100 : 0 }
    }

    struct Insight: Equatable { var title: String; var body: String }

    private(set) var data = DashboardData()
    private(set) var accounts: [Account] = []
    private(set) var recent: [Transaction] = []
    private(set) var rates: [String: RateQuote] = [:]
    private(set) var rateCodes: [String] = []
    private(set) var month: MonthTotals?
    private(set) var topCategory: (name: String, share: Double)?
    private(set) var balance: BalanceState = .loading
    private(set) var isLoading = false
    private(set) var lastLoaded: Date?
    var hideBalances = false

    private let loadDashboard: LoadDashboardUseCase
    private let catalog: CatalogRepository
    private let transactions: TransactionsRepository
    private let loadRates: LoadTransactionRatesUseCase
    private let cacheKey = "dashboard_last_balance_v1"

    init(loadDashboard: LoadDashboardUseCase, catalog: CatalogRepository, transactions: TransactionsRepository) {
        self.loadDashboard = loadDashboard; self.catalog = catalog; self.transactions = transactions
        loadRates = LoadTransactionRatesUseCase(catalog: catalog)
        if let c = Self.readCache(cacheKey) { balance = .cached(c.value, currency: c.currency, at: c.at) }
    }

    var currency: String { data.overview?.currencyCode ?? baseCurrency }
    private var baseCurrency: String { accounts.first(where: { $0.code == "USD" })?.code ?? accounts.first?.code ?? "USD" }
    var monthExpenses: Double? { month?.expenses }

    var insight: Insight? {
        guard let m = month, m.income > 0 else { return nil }
        var body = "Ingresaste \(Fmt.money(m.income, currency: m.currency)) y gastaste \(Fmt.money(m.expenses, currency: m.currency))."
        if let top = topCategory { body = "\(top.name) fue el \(Fmt.percent(top.share)) de tus gastos. ¿Armamos un presupuesto?" }
        let rate = m.savingsRate
        let title = rate >= 0 ? "\(m.label) va con \(Fmt.percent(rate)) de ahorro" : "\(m.label): gastaste más de lo que ingresaste"
        return Insight(title: title, body: body)
    }

    /// 5-minute cache.
    func load(force: Bool = false) async {
        if !force, let lastLoaded, Date.now.timeIntervalSince(lastLoaded) < 300 { return }
        isLoading = true; defer { isLoading = false }
        async let d = loadDashboard()
        async let a = try? catalog.accountBalances()
        async let r = try? transactions.list(filter: .init(period: .all), page: 1, limit: 60)
        async let codes = loadRates.currencies()
        data = await d
        let accs = await a
        accounts = accs ?? accounts
        let txs = await r?.items
        recent = Array((txs ?? recent).prefix(4))
        rateCodes = await codes
        rates = await loadRates(rateCodes)
        computeMonth(txs ?? [])
        resolveBalance(accountsLoaded: accs != nil)
        lastLoaded = .now
    }

    private func resolveBalance(accountsLoaded: Bool) {
        if let o = data.overview {
            balance = .live(o.totalBalance, currency: o.currencyCode)
            Self.writeCache(cacheKey, .init(value: o.totalBalance, currency: o.currencyCode, at: .now))
        } else if accountsLoaded, !accounts.isEmpty {
            let base = baseCurrency
            let total = accounts.reduce(0.0) { sum, a in
                if a.code == base { return sum + a.balance }
                guard let r = ExchangeMath.crossRate(from: a.code, to: base, quotes: rates.mapValues(\.rate)) else { return sum }
                return sum + a.balance * r
            }
            balance = .derived(total, currency: base)
            Self.writeCache(cacheKey, .init(value: total, currency: base, at: .now))
        } else if let c = Self.readCache(cacheKey) {
            balance = .cached(c.value, currency: c.currency, at: c.at)
        } else {
            balance = .unavailable
        }
    }

    /// Month totals: overview KPIs when available, else computed from this month's (or last month's) transactions.
    private func computeMonth(_ txs: [Transaction]) {
        if let o = data.overview, o.monthlyIncome + o.monthlyExpenses > 0 {
            month = MonthTotals(label: Fmt.monthName(.now), income: o.monthlyIncome, expenses: o.monthlyExpenses, currency: o.currencyCode)
        } else {
            let cal = Calendar.current
            let base = baseCurrency
            func totals(for date: Date) -> (MonthTotals, [Transaction]) {
                let inMonth = txs.filter { cal.isDate($0.date, equalTo: date, toGranularity: .month) && $0.displayCurrency == base }
                let inc = inMonth.filter { $0.type == .income }.reduce(0) { $0 + abs($1.amount) }
                let exp = inMonth.filter { $0.type == .expense }.reduce(0) { $0 + abs($1.amount) }
                return (MonthTotals(label: Fmt.monthName(date), income: inc, expenses: exp, currency: base), inMonth)
            }
            var (m, list) = totals(for: .now)
            if m.income + m.expenses == 0, let prev = cal.date(byAdding: .month, value: -1, to: .now) { (m, list) = totals(for: prev) }
            month = m.income + m.expenses > 0 ? m : nil
            let byCat = Dictionary(grouping: list.filter { $0.type == .expense }, by: { $0.categoryName ?? "Otros" })
                .mapValues { $0.reduce(0) { $0 + abs($1.amount) } }
            if let top = byCat.max(by: { $0.value < $1.value }), m.expenses > 0 { topCategory = (top.key, top.value / m.expenses * 100) }
        }
        if let s = data.spending, let top = s.categories.max(by: { $0.amount < $1.amount }) { topCategory = (top.categoryName, top.percentage) }
    }

    func masked(_ s: String) -> String { hideBalances ? "••••••" : s }

    // MARK: cache
    private struct Cached: Codable { var value: Double; var currency: String; var at: Date }
    private static func readCache(_ key: String) -> Cached? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Cached.self, from: $0) }
    }
    private static func writeCache(_ key: String, _ c: Cached) {
        UserDefaults.standard.set(try? JSONEncoder().encode(c), forKey: key)
    }
}
