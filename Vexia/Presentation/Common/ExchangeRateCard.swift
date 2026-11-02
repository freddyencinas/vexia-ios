import SwiftUI

/// "Tasa usada" card shared by every form that converts an account currency to USD.
/// The footer lets each form add its own extra lines (e.g. other snapshot currencies).
struct ExchangeRateCard<Footer: View>: View {
    let code: String
    let rate: Double?
    let isManual: Bool
    let sourceText: String
    let dayRate: Double?
    var onChange: () -> Void
    var onUseDayRate: () -> Void
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasa usada").font(.footnote).foregroundStyle(VexiaColor.textSecondary)
                    Text(rate.map { "1 USD = \(Fmt.grouped($0)) \(Fmt.symbol(code) ?? code)" } ?? String(localized: "Sin tasa para \(code)"))
                        .font(.title3.weight(.bold)).monospacedDigit()
                }
                Spacer()
                Button("Cambiar", action: onChange)
                    .font(.subheadline.weight(.semibold)).buttonStyle(.glass)
            }
            HStack(spacing: 6) {
                Text(isManual ? String(localized: "SOLO ESTE MOVIMIENTO") : String(localized: "AUTOMÁTICA")).font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(isManual ? VexiaColor.amberSoft : VexiaColor.greenSoft, in: .rect(cornerRadius: 6))
                    .foregroundStyle(isManual ? VexiaColor.warningText : VexiaColor.incomeText)
                Text(sourceText).font(.footnote).foregroundStyle(VexiaColor.textSecondary)
            }
            if isManual, let day = dayRate {
                Button("Volver a la tasa del día (\(Fmt.grouped(day)))", action: onUseDayRate).font(.footnote.weight(.semibold))
            }
            footer
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 20))
    }
}

extension ExchangeRateCard where Footer == EmptyView {
    init(code: String, rate: Double?, isManual: Bool, sourceText: String, dayRate: Double?,
         onChange: @escaping () -> Void, onUseDayRate: @escaping () -> Void) {
        self.init(code: code, rate: rate, isManual: isManual, sourceText: sourceText, dayRate: dayRate,
                  onChange: onChange, onUseDayRate: onUseDayRate) { EmptyView() }
    }
}
