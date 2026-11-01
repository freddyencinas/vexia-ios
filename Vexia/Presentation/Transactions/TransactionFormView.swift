import SwiftUI

/// Create/edit transaction (design: "Nueva transacción", "Gasto en otra moneda", "Cambio de divisa").
struct TransactionFormView: View {
    @State var vm: TransactionFormViewModel
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    @State private var showDatePicker = false
    @State private var showMoreOptions = false
    enum Field { case amount, toAmount, rate, note }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !vm.aiNotes.isEmpty { aiNotes }
                    typePicker
                    if vm.draft.type == .transfer { exchangeCards } else { amountHeader }
                    if vm.showsRateCard { rateCard }
                    if vm.needsConversion { fxRateCard }
                    if vm.draft.type != .transfer { categoryGrid }
                    detailsCard
                    if vm.isEditing && !vm.originalSnapshots.isEmpty { snapshotsCard }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { if focus == nil { cta } }
            .navigationTitle(vm.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { focus = nil } }
            }
            .overlay { if vm.isLoadingCatalog { ProgressView().controlSize(.large) } }
            .task {
                await vm.loadCatalog()
                if !vm.isEditing && vm.amountText.isEmpty { focus = .amount }
            }
            .sheet(item: $vm.rateEditRequest) { req in
                RateEditorSheet(vm: RateEditorViewModel(code: req.code, current: vm.rate(for: req.code), previewAmount: req.preview, catalog: vm.catalogRepository),
                                onApplyOnce: { v in vm.applyManual(req.code, v) },
                                onSaveGlobal: { v in await vm.saveGlobal(req.code, v) })
            }
            .errorAlert($vm.errorMessage)
        }
        .presentationDetents([.large])
    }

    // MARK: Sections

    private var aiNotes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sugerido por Vexia", systemImage: "sparkles").font(.footnote.weight(.semibold)).foregroundStyle(VexiaColor.violet)
            ForEach(vm.aiNotes, id: \.self) { Text($0).font(.footnote) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(VexiaColor.violetSoft, in: .rect(cornerRadius: 14))
    }

    private var typePicker: some View {
        Picker("Tipo", selection: $vm.draft.type) {
            ForEach(TransactionType.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .disabled(vm.isEditing && vm.draft.type == .transfer)
        .onChange(of: vm.draft.type) { vm.typeChanged(); Task { await vm.accountsChanged() } }
    }

    private var amountHeader: some View {
        VStack(spacing: 8) {
            accountMenu(selection: $vm.draft.accountId, label: vm.fromAccount.map { "\($0.name) · \(Fmt.symbol($0.code) ?? $0.code)" } ?? "Elegir cuenta")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.symbol(vm.accountCode) ?? vm.accountCode).font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(VexiaColor.textSecondary)
                TextField("0", text: $vm.amountText)
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(vm.draft.type == .income ? VexiaColor.incomeText : .primary)
                    .keyboardType(.decimalPad).fixedSize().focused($focus, equals: .amount)
                    .onChange(of: vm.amountText) { if focus == .amount { vm.amountChanged() } }
                    .accessibilityLabel("Monto")
            }
            if let usd = vm.equivalentUSD {
                Text("≈ \(Fmt.money(usd, currency: "USD"))").font(.headline).foregroundStyle(VexiaColor.textSecondary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .onChange(of: vm.draft.accountId) { Task { await vm.accountsChanged() } }
    }

    private var rateCard: some View {
        let code = vm.accountCode
        let manual = vm.isManual(code)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasa usada").font(.footnote).foregroundStyle(VexiaColor.textSecondary)
                    Text(vm.usedRate.map { "1 USD = \(Fmt.grouped($0)) \(Fmt.symbol(code) ?? code)" } ?? "Sin tasa para \(code)")
                        .font(.title3.weight(.bold)).monospacedDigit()
                }
                Spacer()
                Button("Cambiar") { vm.editRate(code, preview: vm.amountValue > 0 ? vm.amountValue : nil) }
                    .font(.subheadline.weight(.semibold)).buttonStyle(.glass)
            }
            HStack(spacing: 6) {
                Text(manual ? "SOLO ESTE MOVIMIENTO" : "AUTOMÁTICA").font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(manual ? VexiaColor.amberSoft : VexiaColor.greenSoft, in: .rect(cornerRadius: 6))
                    .foregroundStyle(manual ? VexiaColor.warningText : VexiaColor.incomeText)
                Text(vm.rateSourceText).font(.footnote).foregroundStyle(VexiaColor.textSecondary)
            }
            if manual, let day = vm.dayRate {
                Button("Volver a la tasa del día (\(Fmt.grouped(day)))") { vm.useDayRate() }.font(.footnote.weight(.semibold))
            }
            let also = vm.alsoSavedIn
            if !also.isEmpty {
                Divider()
                Text("También se guardará en").font(.subheadline.weight(.semibold))
                ForEach(also, id: \.code) { item in
                    HStack {
                        Text(item.code == "USD" ? "Dólares" : (RatesViewModel.name(item.code) + " · 1 USD = \(Fmt.grouped(item.rate))"))
                            .foregroundStyle(VexiaColor.textSecondary)
                        Spacer()
                        Text(Fmt.money(item.amount, currency: item.code)).fontWeight(.semibold).monospacedDigit()
                    }
                    .font(.subheadline)
                }
                Text("Estas conversiones quedan fijas con la tasa de hoy.").font(.caption).foregroundStyle(VexiaColor.textSecondary)
            }
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    private var exchangeCards: some View {
        VStack(spacing: 6) {
            ZStack {
                VStack(spacing: 6) {
                    sideCard(title: "Envías desde", account: vm.fromAccount, selection: $vm.draft.accountId) {
                        TextField("0", text: $vm.amountText)
                            .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                            .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                            .focused($focus, equals: .amount)
                            .onChange(of: vm.amountText) { if focus == .amount { vm.amountChanged() } }
                            .accessibilityLabel("Monto que envías")
                    }
                    sideCard(title: "Recibes en", account: vm.toAccount, selection: $vm.draft.toAccountId, exclude: vm.draft.accountId) {
                        if vm.needsConversion {
                            TextField("0", text: $vm.toAmountText)
                                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(VexiaColor.incomeText)
                                .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                                .focused($focus, equals: .toAmount)
                                .onChange(of: vm.toAmountText) { if focus == .toAmount { vm.userEditedToAmount() } }
                                .accessibilityLabel("Monto que recibes")
                        } else {
                            Text(vm.amountText.isEmpty ? "0" : vm.amountText).font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(VexiaColor.incomeText)
                        }
                    }
                }
                Button { vm.swapAccounts() } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.headline).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(VexiaColor.brandFill, in: .circle)
                        .overlay(Circle().stroke(Color(.systemGroupedBackground), lineWidth: 4))
                }
                .accessibilityLabel("Invertir cuentas")
                .disabled(vm.draft.toAccountId == nil)
            }
        }
        .onChange(of: vm.draft.accountId) { Task { await vm.accountsChanged() } }
        .onChange(of: vm.draft.toAccountId) { Task { await vm.accountsChanged() } }
    }

    private func sideCard<Amount: View>(title: String, account: Account?, selection: Binding<String?>, exclude: String? = nil,
                                        @ViewBuilder amount: () -> Amount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                if let a = account { Text("Saldo \(Fmt.money(a.balance, currency: a.code))") }
            }
            .font(.footnote).foregroundStyle(VexiaColor.textSecondary)
            HStack {
                accountMenu(selection: selection, label: account.map { "\($0.name) · \(Fmt.symbol($0.code) ?? $0.code)" } ?? "Elegir cuenta", exclude: exclude)
                Spacer()
                amount()
            }
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 22))
    }

    private var fxRateCard: some View {
        let from = vm.accountCode, to = vm.toCode
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasa").font(.footnote).foregroundStyle(VexiaColor.textSecondary)
                    Text(vm.fxRateValue.map { vm.rateLabel(from: from, to: to, rate: $0) } ?? "Sin tasa").font(.title3.weight(.bold)).monospacedDigit()
                }
                Spacer()
            }
            Picker("Tasa a usar", selection: Binding(get: { vm.usesDayFXRate }, set: { if $0 { vm.useDayFXRate() } else { focus = .rate } })) {
                Text(vm.dayCrossRate.map { "Del día · \(Fmt.grouped(dayDisplay($0, from: from, to: to)))" } ?? "Del día").tag(true)
                Text("La que me dieron").tag(false)
            }
            .pickerStyle(.segmented)
            if !vm.usesDayFXRate || focus == .rate {
                LabeledContent("Tasa \(from) → \(to)") {
                    TextField("0", text: $vm.exchangeRateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .monospacedDigit().focused($focus, equals: .rate)
                        .onChange(of: vm.exchangeRateText) { if focus == .rate { vm.userEditedRate() } }
                }
                .font(.subheadline)
            }
            if let diff = vm.fxShortfall, let day = vm.dayCrossRate {
                Text("Con la tasa del día recibirías \(Fmt.money(vm.amountValue * day, currency: to)). Diferencia: \(Fmt.money(abs(diff), currency: to)) \(diff > 0 ? "menos" : "más").")
                    .font(.footnote).foregroundStyle(VexiaColor.warningText)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(VexiaColor.amberSoft, in: .rect(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    private func dayDisplay(_ r: Double, from: String, to: String) -> Double { to == "USD" && r > 0 ? 1 / r : r }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Categoría").font(.subheadline.weight(.semibold))
                Spacer()
                if !vm.aiNotes.isEmpty || vm.draft.categoryId != nil && !vm.isEditing && vm.aiNotes.isEmpty == false {
                    Label("Sugerida por Vexia", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(VexiaColor.violet)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(vm.gridCategories) { c in
                    let on = vm.draft.categoryId == c.id
                    Button { vm.draft.categoryId = c.id } label: {
                        VStack(spacing: 4) {
                            if let e = CategorySymbol.emoji(c.icon) { Text(e).font(.title2) }
                            else { Image(systemName: CategorySymbol.of(icon: c.icon, name: c.name)).font(.title3).foregroundStyle(on ? VexiaColor.brandBlue : VexiaColor.textSecondary) }
                            Text(c.name).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 66)
                        .background(on ? VexiaColor.tintSoft : Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? VexiaColor.brandBlue : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Menu {
                    Picker("Categoría", selection: $vm.draft.categoryId) {
                        ForEach(vm.filteredCategories) { Text($0.name).tag(Optional($0.id)) }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "ellipsis").font(.title3).foregroundStyle(VexiaColor.textSecondary)
                        Text("Más").font(.caption2.weight(.semibold)).foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                }
            }
        }
        .padding(12)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Fecha")
                Spacer()
                dateChip("Hoy", Calendar.current.isDateInToday(vm.draft.date)) { vm.draft.date = .now; showDatePicker = false }
                dateChip("Ayer", Calendar.current.isDateInYesterday(vm.draft.date)) {
                    vm.draft.date = Calendar.current.date(byAdding: .day, value: -1, to: .now)!; showDatePicker = false
                }
                dateChip(isOtherDate ? Fmt.shortDate(vm.draft.date) : "Otra…", isOtherDate) { showDatePicker.toggle() }
            }
            .frame(minHeight: 52)
            if showDatePicker {
                DatePicker("Fecha", selection: $vm.draft.date, in: ...Date.now.addingTimeInterval(86_400 * 365), displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            Divider()
            TextField(vm.draft.type == .transfer ? "Descripción (opcional)" : "Añadir nota (opcional)", text: $vm.draft.description, axis: .vertical)
                .focused($focus, equals: .note)
                .frame(minHeight: 52)
            if vm.draft.type != .transfer {
                Divider()
                DisclosureGroup(isExpanded: $showMoreOptions) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $vm.draft.isRecurring) { Label("Recurrente", systemImage: "repeat") }
                        if vm.draft.isRecurring {
                            Picker("Frecuencia", selection: $vm.draft.recurringFrequency) {
                                ForEach(TransactionDraft.RecurringFrequency.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        HStack {
                            Image(systemName: "number").foregroundStyle(VexiaColor.textSecondary)
                            TextField("Añadir etiqueta", text: $vm.tagInput).onSubmit(vm.addTag).textInputAutocapitalization(.never)
                        }
                        if !vm.draft.tags.isEmpty {
                            FlowChips {
                                ForEach(vm.draft.tags, id: \.self) { tag in
                                    Button { vm.draft.tags.removeAll { $0 == tag } } label: { Label("#\(tag)", systemImage: "xmark").font(.caption) }
                                        .buttonStyle(.glass)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } label: {
                    HStack {
                        Text("Más opciones")
                        Spacer()
                        Text(optionsSummary).font(.footnote).foregroundStyle(VexiaColor.textSecondary)
                    }
                }
                .frame(minHeight: 52)
            }
        }
        .padding(.horizontal, 14)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    private var snapshotsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conversiones registradas").font(.subheadline.weight(.semibold))
            ForEach(vm.originalSnapshots, id: \.currencyId) { s in
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

    private var cta: some View {
        Button {
            Task { if await vm.submit() { onSaved(); dismiss() } }
        } label: {
            HStack {
                if vm.isSaving { ProgressView().tint(.white) }
                Text(vm.ctaTitle).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.glassProminent).controlSize(.large)
        .tint(vm.draft.type == .income ? VexiaColor.brandGreen : VexiaColor.brandBlue)
        .disabled(!vm.missingFields.isEmpty || vm.isSaving)
        .padding(.horizontal).padding(.bottom, 8)
    }

    // MARK: helpers

    private var isOtherDate: Bool { !Calendar.current.isDateInToday(vm.draft.date) && !Calendar.current.isDateInYesterday(vm.draft.date) }
    private var optionsSummary: String {
        var parts: [String] = []
        if vm.draft.isRecurring { parts.append(vm.draft.recurringFrequency.title) }
        if !vm.draft.tags.isEmpty { parts.append("\(vm.draft.tags.count) etiqueta\(vm.draft.tags.count == 1 ? "" : "s")") }
        return parts.isEmpty ? "Recurrente · Etiquetas" : parts.joined(separator: " · ")
    }

    private func dateChip(_ title: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 32)
                .background(on ? VexiaColor.brandFill : Color(.secondarySystemBackground), in: .capsule)
                .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func accountMenu(selection: Binding<String?>, label: String, exclude: String? = nil) -> some View {
        Menu {
            Picker("Cuenta", selection: selection) {
                ForEach(vm.accounts.filter { $0.id != exclude }) { a in
                    Label("\(a.name) · \(Fmt.money(a.balance, currency: a.code))", systemImage: a.type.symbol).tag(Optional(a.id))
                }
            }
        } label: {
            HStack(spacing: 4) { Text(label).lineLimit(1); Image(systemName: "chevron.down").font(.caption) }
                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(.background, in: .capsule)
                .overlay(Capsule().strokeBorder(Color(.separator)))
        }
    }
}
