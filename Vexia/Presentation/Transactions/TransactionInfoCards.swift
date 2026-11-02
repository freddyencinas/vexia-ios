import SwiftUI

/// AI suggestion notes shown above the form.
struct TransactionAINotes: View {
    let notes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sugerido por Vexia", systemImage: "sparkles").font(.footnote.weight(.semibold)).foregroundStyle(VexiaColor.violet)
            ForEach(notes, id: \.self) { Text($0).font(.footnote) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(VexiaColor.violetSoft, in: .rect(cornerRadius: 14))
    }
}

/// Read-only conversions recorded when the transaction was created (edit mode).
struct TransactionSnapshotsCard: View {
    let snapshots: [CurrencySnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conversiones registradas").font(.subheadline.weight(.semibold))
            ForEach(snapshots, id: \.currencyId) { s in
                HStack {
                    Text(s.currencyCode).bold()
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(Fmt.money(s.convertedAmount, currency: s.currencyCode)).monospacedDigit()
                        Text("TC \(Fmt.grouped(s.exchangeRate, decimals: 4))").font(.caption2).foregroundStyle(VexiaColor.textSecondary)
                    }
                }
                .font(.subheadline)
            }
            Text("Tasas guardadas al momento de la transacción.").font(.caption).foregroundStyle(VexiaColor.textSecondary)
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 20))
    }
}
