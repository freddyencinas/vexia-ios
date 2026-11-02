import SwiftUI

/// Rate used to convert a foreign-currency amount to USD.
struct TransactionRateCard: View {
    @Bindable var vm: TransactionFormViewModel

    var body: some View {
        let code = vm.accountCode
        return ExchangeRateCard(code: code, rate: vm.usedRate, isManual: vm.isManual(code), sourceText: vm.rateSourceText, dayRate: vm.dayRate,
                                onChange: { vm.editRate(code, preview: vm.amountValue > 0 ? vm.amountValue : nil) },
                                onUseDayRate: { vm.useDayRate() }) {
            let also = vm.alsoSavedIn
            if !also.isEmpty {
                Divider()
                Text("También se guardará en").font(.subheadline.weight(.semibold))
                ForEach(also, id: \.code) { item in
                    HStack {
                        Text(item.code == "USD" ? String(localized: "Dólares") : (RatesViewModel.name(item.code) + " · 1 USD = \(Fmt.grouped(item.rate))"))
                            .foregroundStyle(VexiaColor.textSecondary)
                        Spacer()
                        Text(Fmt.money(item.amount, currency: item.code)).fontWeight(.semibold).monospacedDigit()
                    }
                    .font(.subheadline)
                }
                Text("Estas conversiones quedan fijas con la tasa de hoy.").font(.caption).foregroundStyle(VexiaColor.textSecondary)
            }
        }
    }
}

/// Cross-currency rate for transfers (day rate vs. the one the user was given).
struct TransactionFXRateCard: View {
    @Bindable var vm: TransactionFormViewModel
    var focus: FocusState<TransactionFormView.Field?>.Binding

    var body: some View {
        let from = vm.accountCode, to = vm.toCode
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasa").font(.footnote).foregroundStyle(VexiaColor.textSecondary)
                    Text(vm.fxRateValue.map { vm.rateLabel(from: from, to: to, rate: $0) } ?? String(localized: "Sin tasa")).font(.title3.weight(.bold)).monospacedDigit()
                }
                Spacer()
            }
            Picker("Tasa a usar", selection: Binding(get: { vm.usesDayFXRate }, set: { if $0 { vm.useDayFXRate() } else { focus.wrappedValue = .rate } })) {
                Text(vm.dayCrossRate.map { String(localized: "Del día · \(Fmt.grouped(dayDisplay($0, to: to)))") } ?? String(localized: "Del día")).tag(true)
                Text("La que me dieron").tag(false)
            }
            .pickerStyle(.segmented)
            if !vm.usesDayFXRate || focus.wrappedValue == .rate {
                LabeledContent("Tasa \(from) → \(to)") {
                    TextField("0", text: $vm.exchangeRateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .monospacedDigit().focused(focus, equals: .rate)
                        .onChange(of: vm.exchangeRateText) { if focus.wrappedValue == .rate { vm.userEditedRate() } }
                }
                .font(.subheadline)
            }
            if let diff = vm.fxShortfall, let day = vm.dayCrossRate {
                let atDay = Fmt.money(vm.amountValue * day, currency: to), gap = Fmt.money(abs(diff), currency: to)
                // Whole sentences per case: a spliced "menos"/"más" can't be reordered by translators.
                Group {
                    if diff > 0 { Text("Con la tasa del día recibirías \(atDay). Diferencia: \(gap) menos.") }
                    else { Text("Con la tasa del día recibirías \(atDay). Diferencia: \(gap) más.") }
                }
                .font(.footnote).foregroundStyle(VexiaColor.warningText)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(VexiaColor.amberSoft, in: .rect(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    private func dayDisplay(_ r: Double, to: String) -> Double { to == "USD" && r > 0 ? 1 / r : r }
}
