import SwiftUI

/// What Siri says for a spending question. Full sentences: also read aloud (AirPods, CarPlay).
enum SpendingAnswer {
    static func sentence(_ r: ConsultSpendingUseCase.Report) -> String {
        let lead = lead(r.period)
        let amount = Fmt.money(r.total, currency: r.currency)
        let moves = r.count == 1 ? String(localized: "1 movimiento") : String(localized: "\(r.count) movimientos")
        if let name = r.categoryName {
            return r.total > 0
                ? String(localized: "\(lead) gastaste \(amount) en \(name), \(moves).")
                : String(localized: "\(lead) no tienes gastos en \(name).")
        }
        guard r.total > 0 else { return String(localized: "\(lead) no registraste gastos.") }
        let base = String(localized: "\(lead) gastaste \(amount) en \(moves).")
        guard let top = r.topCategories.first else { return base }
        return base + " " + String(localized: "Lo más alto fue \(top.categoryName), con \(Fmt.money(top.amount, currency: r.currency)).")
    }

    static func lead(_ p: SpendingPeriod) -> String {
        switch p {
        case .today: String(localized: "Hoy")
        case .thisWeek: String(localized: "Esta semana")
        case .thisMonth: String(localized: "Este mes")
        case .lastMonth: String(localized: "El mes pasado")
        }
    }
}

/// Snippet under Siri's answer: total, then the biggest categories (or expenses of the asked category).
struct SiriSpendingCard: View {
    let report: ConsultSpendingUseCase.Report

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SpendingAnswer.lead(report.period)).font(.caption).foregroundStyle(VexiaColor.textSecondary)
                    Text(report.categoryName ?? String(localized: "Gastos")).font(.headline).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Fmt.money(report.total, currency: report.currency)).font(.title3.weight(.bold).monospacedDigit())
            }
            ForEach(report.topCategories) { c in
                row(c.categoryName, amount: c.amount, fraction: report.total > 0 ? c.amount / report.total : 0)
            }
            ForEach(report.topExpenses) { e in
                row(e.description.isEmpty ? e.categoryName : e.description, amount: e.amount, fraction: nil)
            }
        }
        .padding()
    }

    private func row(_ title: String, amount: Double, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline).lineLimit(1)
                Spacer(minLength: 8)
                Text(Fmt.money(amount, currency: report.currency)).font(.subheadline.monospacedDigit()).foregroundStyle(VexiaColor.textSecondary)
            }
            if let fraction {
                GeometryReader { geo in
                    Capsule().fill(VexiaColor.expenseFill)
                        .frame(width: BarMetrics.width(geo.size.width, fraction))
                }
                .frame(height: 4)
            }
        }
    }
}

#Preview {
    SiriSpendingCard(report: .init(
        period: .thisMonth, currency: "BOB", total: 1417.56, count: 18, category: nil, categoryName: nil,
        topCategories: [
            .init(categoryId: "1", categoryCode: "UTILITIES", categoryName: "Servicios básicos", amount: 1111.46, percentage: 78, transactionCount: 4),
            .init(categoryId: "2", categoryCode: "", categoryName: "Almuerzo", amount: 140, percentage: 10, transactionCount: 2),
        ],
        topExpenses: []))
}
