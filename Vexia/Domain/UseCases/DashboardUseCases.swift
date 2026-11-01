import Foundation

/// Loads the 4 dashboard sections in parallel; each one fails independently
/// (per-request timeouts).
struct LoadDashboardUseCase {
    let repo: DashboardRepository

    func callAsFunction(now: Date = .now, calendar: Calendar = .current) async -> DashboardData {
        let monthStart = calendar.dateInterval(of: .month, for: now)!.start
        async let o = try? repo.overview()
        async let c = try? repo.cashFlow(period: "6m", groupBy: "month")
        async let s = try? repo.spending(start: monthStart, end: now)
        async let p = try? repo.performance()
        return await DashboardData(overview: o, cashFlow: c, spending: s, performance: p)
    }
}
