import SwiftUI

/// Amount entry for assets with many decimals (BTC 8, shares 6).
/// Type units or dollars (⇅), see the live equivalent, and use quick chips:
/// % of the holding when selling, dollar amounts when buying.
struct AssetAmountInput: View {
    @Binding var quantity: String
    let unit: String
    let maxDecimals: Int
    let unitPrice: Double?
    var available: Double? = nil
    var quickFiat: [Int] = [10, 50, 100]
    var focus: FocusState<Bool>.Binding

    @State private var inFiat = false
    @State private var fiatText = ""
    @State private var tapped = 0

    private var price: Decimal? { unitPrice.flatMap { $0 > 0 ? AmountMath.decimal($0) : nil } }
    private var units: Decimal? { AmountMath.parse(quantity) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if inFiat { Text(verbatim: "$").font(.title.weight(.bold)).foregroundStyle(VexiaColor.textSecondary) }
                TextField("0", text: inFiat ? fiatBinding : unitsBinding)
                    .keyboardType(.decimalPad)
                    .focused(focus)
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: 220)
                    .accessibilityLabel(inFiat ? Text("Monto en dólares") : Text("Cantidad"))
                if !inFiat { Text(verbatim: unit).font(.title3.weight(.semibold)).foregroundStyle(VexiaColor.textSecondary) }
            }
            .frame(maxWidth: .infinity)

            if price != nil || inFiat {
                HStack(spacing: 8) {
                    Text(equivalentText).font(.subheadline).monospacedDigit().foregroundStyle(VexiaColor.textSecondary)
                    if price != nil {
                        Button { toggleUnit() } label: {
                            Image(systemName: "arrow.up.arrow.down").font(.footnote.weight(.semibold)).frame(width: 28, height: 28)
                        }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                        .accessibilityLabel(inFiat ? Text("Escribir en \(unit)") : Text("Escribir en dólares"))
                    }
                }
            }
            chips
        }
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: tapped)
        .onChange(of: unitPrice) { if inFiat { recomputeFromFiat() } }
    }

    // MARK: Chips

    @ViewBuilder private var chips: some View {
        if let available, available > 0 {
            HStack(spacing: 8) {
                ForEach([25, 50, 75, 100], id: \.self) { p in
                    chip(p == 100 ? String(localized: "Máx") : "\(p)%") {
                        inFiat = false
                        setUnits(AmountMath.portion(of: AmountMath.decimal(available), percent: p, maxDecimals: maxDecimals))
                    }
                }
            }
        } else if let price {
            HStack(spacing: 8) {
                ForEach(quickFiat, id: \.self) { v in
                    chip("$\(v)") {
                        inFiat = true
                        fiatText = "\(v)"
                        setUnits(AmountMath.units(fromFiat: Decimal(v), price: price, maxDecimals: maxDecimals))
                    }
                }
            }
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button { tapped += 1; action() } label: {
            Text(verbatim: title).font(.subheadline.weight(.semibold)).monospacedDigit().frame(minWidth: 44)
        }
        .buttonStyle(.glass).controlSize(.small)
    }

    // MARK: Logic

    private var unitsBinding: Binding<String> {
        Binding(get: { quantity }, set: { quantity = AmountMath.sanitize($0, maxDecimals: maxDecimals) })
    }

    private var fiatBinding: Binding<String> {
        Binding(get: { fiatText }, set: { fiatText = AmountMath.sanitize($0, maxDecimals: 2); recomputeFromFiat() })
    }

    private var equivalentText: String {
        if inFiat { return "≈ \(AmountMath.editable(units ?? 0, maxDecimals: maxDecimals)) \(unit)" }
        guard let price, let units else { return "≈ $0" }
        return "≈ \(Fmt.money(AmountMath.double(AmountMath.fiat(units: units, price: price))))"
    }

    private func toggleUnit() {
        tapped += 1
        if !inFiat, let price, let units {
            fiatText = AmountMath.editable(AmountMath.fiat(units: units, price: price), maxDecimals: 2)
        }
        inFiat.toggle()
    }

    private func recomputeFromFiat() {
        guard let price, let fiat = AmountMath.parse(fiatText) else { if fiatText.isEmpty { quantity = "" }; return }
        quantity = AmountMath.editable(AmountMath.units(fromFiat: fiat, price: price, maxDecimals: maxDecimals), maxDecimals: maxDecimals)
    }

    private func setUnits(_ d: Decimal) { quantity = AmountMath.editable(d, maxDecimals: maxDecimals) }
}

#Preview("Comprar BTC") {
    @Previewable @State var q = ""
    @Previewable @FocusState var f: Bool
    Form { AssetAmountInput(quantity: $q, unit: "BTC", maxDecimals: 8, unitPrice: 98_500, focus: $f) }
}

#Preview("Vender acciones") {
    @Previewable @State var q = "1"
    @Previewable @FocusState var f: Bool
    Form { AssetAmountInput(quantity: $q, unit: "acciones", maxDecimals: 6, unitPrice: 230, available: 3.5, focus: $f) }
}
