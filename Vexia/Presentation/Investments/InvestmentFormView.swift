import SwiftUI

/// Comprar o vender (design): stepper, today's price, fee, account, estimated profit / new average, max validation.
struct InvestmentFormView: View {
    @State var vm: InvestmentFormViewModel
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool
    @State private var showSectorPicker = false
    @State private var showExchangePicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Operación", selection: $vm.draft.operationType) {
                        Text("Comprar").tag(OperationType.buy)
                        Text("Vender").tag(OperationType.sell)
                    }
                    .pickerStyle(.segmented).disabled(vm.editingId != nil)
                    .listRowBackground(Color.clear).listRowInsets(.init())
                }
                Section {
                    if vm.holding == nil && vm.editingId == nil {
                        TextField(vm.isCrypto ? String(localized: "Símbolo (BTC, ETH…)") : String(localized: "Símbolo (AAPL, MSFT…)"), text: $vm.draft.symbol).focused($typing)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    } else {
                        LabeledContent(vm.isCrypto ? String(localized: "Cripto") : String(localized: "Acción")) {
                            let owned = vm.holding.map { String(localized: "  · tienes \(Fmt.quantity($0.quantity, crypto: vm.isCrypto))") } ?? ""
                            Text("\(Text(vm.draft.symbol.uppercased()).fontWeight(.semibold))\(Text(owned).foregroundStyle(VexiaColor.textSecondary))")
                        }
                    }
                    if vm.isCrypto {
                        selectionRow("Exchange", value: vm.exchangeName) { showExchangePicker = true }
                        Toggle("Stablecoin", isOn: $vm.draft.isStablecoin)
                    } else if vm.holding == nil {
                        selectionRow("Sector", value: vm.sectorName) { showSectorPicker = true }
                    }
                }
                Section {
                    // Price first: the amount control converts with it ($ mode, quick chips)
                    LabeledContent(vm.isSell ? String(localized: "Precio de venta") : String(localized: "Precio por unidad")) {
                        TextField("0,00", text: $vm.priceText).focused($typing).keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                    }
                    AssetAmountInput(quantity: $vm.quantityText, unit: vm.unitLabel, maxDecimals: vm.maxDecimals,
                                     unitPrice: vm.unitPrice, available: vm.sellAvailable, focus: $typing)
                    if vm.overMax, let m = vm.maxSell {
                        Text("Solo tienes \(Fmt.quantity(m, crypto: vm.isCrypto)) para vender.").font(.footnote.weight(.semibold)).foregroundStyle(VexiaColor.expenseText)
                    }
                    LabeledContent("Comisión") {
                        TextField("0,00", text: $vm.feeText).focused($typing).keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                    }
                    if !vm.accounts.isEmpty && vm.editingId == nil {
                        Picker(vm.isSell ? String(localized: "Recibir en") : String(localized: "Pagar con"), selection: $vm.draft.accountId) {
                            ForEach(vm.accounts) { Text("\($0.name) · \(Fmt.money($0.balance, currency: $0.code))").tag(Optional($0.id)) }
                        }
                    }
                    DatePicker("Fecha", selection: $vm.draft.date, displayedComponents: .date)
                }
                if vm.showsRateCard {
                    Section {
                        ExchangeRateCard(code: vm.accountCode, rate: vm.usedRate, isManual: vm.isManualRate, sourceText: vm.rateSourceText,
                                         dayRate: vm.dayRate, onChange: { vm.editRate() }, onUseDayRate: { vm.useDayRate() })
                            .listRowInsets(.init()).listRowBackground(Color.clear)
                    }
                }
                Section {
                    LabeledContent(vm.isSell ? String(localized: "Recibirás") : String(localized: "Pagarás")) { Text(Fmt.money(vm.total)).fontWeight(.bold).monospacedDigit() }
                    if let local = vm.totalInAccountCurrency {
                        LabeledContent(vm.isSell ? String(localized: "Entra a tu cuenta") : String(localized: "Sale de tu cuenta")) {
                            Text(Fmt.money(local, currency: vm.accountCode)).fontWeight(.semibold).monospacedDigit()
                        }
                    }
                    if let p = vm.estimatedProfit {
                        LabeledContent("Ganancia estimada") {
                            Text((p >= 0 ? "+" : "−") + Fmt.money(abs(p))).fontWeight(.bold)
                                .foregroundStyle(p >= 0 ? VexiaColor.incomeText : VexiaColor.expenseText)
                        }
                    }
                } footer: {
                    if let h = vm.holding, vm.isSell { Text("Calculado con tu precio promedio de \(Fmt.money(h.avgPrice)).") }
                    else if let avg = vm.newAverage { Text("Tu nuevo precio promedio será \(Fmt.money(avg)).") }
                }
                Section { TextField("Notas (opcional)", text: $vm.draft.notes, axis: .vertical).focused($typing) }
            }
            .navigationTitle(vm.editingId != nil ? String(localized: "Editar operación") : (vm.isSell ? String(localized: "Vender") : String(localized: "Comprar")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { typing = false } } }
            .safeAreaInset(edge: .bottom) {
                if !typing {
                Button {
                    Task { if await vm.submit() { onSaved(); dismiss() } }
                } label: { Text(vm.ctaTitle).font(.headline).frame(maxWidth: .infinity, minHeight: 34) }
                .buttonStyle(.glassProminent).controlSize(.large)
                .tint(vm.isSell ? VexiaColor.expenseText : VexiaColor.brandBlue)
                .disabled(!vm.canSubmit)
                .padding(.horizontal).padding(.bottom, 8)
                }
            }
            .task { async let a: Void = vm.loadAccounts(); async let s: Void = vm.loadCategories(); _ = await (a, s) }
            .task(id: vm.draft.accountId) { await vm.loadRate() }
            .sheet(item: $vm.rateEditRequest) { req in
                if let catalog = vm.catalogRepository {
                    RateEditorSheet(vm: RateEditorViewModel(code: req.code, current: vm.usedRate, previewAmount: req.preview, catalog: catalog),
                                    onApplyOnce: { v in vm.applyManual(req.code, v) },
                                    onSaveGlobal: { v in try await vm.saveGlobal(req.code, v) })
                }
            }
            .sheet(isPresented: $showExchangePicker) {
                CategoryPickerSheet(categories: vm.exchanges, selection: $vm.exchangeId, title: "Exchange", searchPrompt: "Buscar exchange")
            }
            .sheet(isPresented: $showSectorPicker) {
                CategoryPickerSheet(categories: vm.sectors, selection: $vm.sectorId, title: "Sector", searchPrompt: "Buscar sector")
            }
            .errorAlert($vm.errorMessage)
        }
    }

    /// Tappable row that opens a picker sheet (sector, exchange).
    private func selectionRow(_ title: LocalizedStringKey, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LabeledContent(title) {
                // HStack: LabeledContent stacks multiple content views vertically
                HStack(spacing: 6) {
                    Text(value ?? String(localized: "Opcional"))
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                }
                .foregroundStyle(value == nil ? VexiaColor.textSecondary : VexiaColor.brandBlue)
            }
        }
        .foregroundStyle(.primary)
    }
}
