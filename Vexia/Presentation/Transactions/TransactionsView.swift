import SwiftUI

/// Movimientos (design: month selector, visible filter chips, single summary card, daily totals).
struct TransactionsView: View {
    @State var vm: TransactionsListViewModel
    let makeForm: (Transaction?) -> TransactionFormViewModel
    @State private var editing: Transaction?

    var body: some View {
        List {
            Section {
                monthSelector
                chips
                summaryCard
            }
            .listRowBackground(Color.clear)
            .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)

            switch vm.state {
            case .failed(let m):
                ContentUnavailableView {
                    Label("No pudimos cargar tus movimientos", systemImage: "wifi.exclamationmark")
                } description: { Text(m) } actions: {
                    Button("Reintentar") { Task { await vm.reload() } }.buttonStyle(.glassProminent)
                }
                .listRowBackground(Color.clear)
            case .loaded where vm.items.isEmpty:
                ContentUnavailableView {
                    Label(vm.filter.search.isEmpty ? "Sin movimientos" : "Sin resultados", systemImage: "tray")
                } description: {
                    Text(vm.filter.search.isEmpty
                         ? (vm.month == nil ? "Registra uno con el botón +." : "No hay registros en \(vm.monthTitle.lowercased()). Registra uno con el botón + o revisa otro mes.")
                         : "Prueba con otra palabra o monto.")
                } actions: {
                    if vm.month != nil { Button("Ver todo el historial") { vm.showAllTime() }.buttonStyle(.glass) }
                }
                .listRowBackground(Color.clear)
            case .idle where vm.items.isEmpty, .loading where vm.items.isEmpty:
                ForEach(0..<6, id: \.self) { _ in TransactionRow(tx: Self.placeholder).redacted(reason: .placeholder) }
            default:
                ForEach(vm.sections, id: \.day) { section in
                    Section {
                        ForEach(section.items) { tx in
                            Button { editing = tx } label: { TransactionRow(tx: tx) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    if !tx.isSystemGenerated {
                                        Button(role: .destructive) { Task { await vm.requestDelete(tx) } } label: { Label("Eliminar", systemImage: "trash") }
                                    }
                                }
                                .contextMenu {
                                    Button { editing = tx } label: { Label("Editar", systemImage: "pencil") }
                                    Button(role: .destructive) { Task { await vm.requestDelete(tx) } } label: { Label("Eliminar", systemImage: "trash") }
                                }
                                .task { await vm.loadMoreIfNeeded(current: tx) }
                        }
                    } header: {
                        HStack {
                            Text(section.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "es"))).uppercased())
                            Spacer()
                            Text(vm.dayTotal(section.items)).monospacedDigit()
                        }
                        .font(.footnote.weight(.semibold)).foregroundStyle(VexiaColor.textSecondary)
                    }
                }
                if vm.isLoadingMore { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $vm.filter.search, prompt: "Buscar por nombre o monto")
        .onChange(of: vm.filter.search) { vm.scheduleReload() }
        .onChange(of: vm.filter.type) { Task { await vm.reload() } }
        .onChange(of: vm.filter.accountId) { Task { await vm.reload() } }
        .onChange(of: vm.filter.categoryId) { Task { await vm.reload() } }
        .refreshable { await vm.reload() }
        .task {
            await vm.loadCatalog()
            if case .idle = vm.state { await vm.reload() }
        }
        .sheet(item: $editing) { tx in
            TransactionFormView(vm: makeForm(tx)) { Task { await vm.reload() } }
        }
        .confirmationDialog("¿Eliminar transacción?", item: $vm.pendingDelete) { _ in
            Button("Eliminar", role: .destructive) { Task { await vm.confirmDelete() } }
        } message: { _ in
            Text(vm.deleteWarning ?? "Esta acción no se puede deshacer.")
        }
        .errorAlert($vm.errorMessage)
    }

    private var monthSelector: some View {
        HStack {
            Button { vm.shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Mes anterior")
            Spacer()
            Menu {
                Button("Este mes") { vm.month = Calendar.current.dateInterval(of: .month, for: .now)!.start; Task { await vm.reload() } }
                Button("Todo el historial") { vm.showAllTime() }
            } label: {
                Text(vm.monthTitle).font(.headline).foregroundStyle(.primary)
            }
            Spacer()
            Button { vm.shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Mes siguiente")
                .disabled(!vm.canGoForward)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("Todos", vm.filter.type == nil) { vm.filter.type = nil }
                chip("Gastos", vm.filter.type == .expense) { vm.filter.type = .expense }
                chip("Ingresos", vm.filter.type == .income) { vm.filter.type = .income }
                chip("Transferencias", vm.filter.type == .transfer) { vm.filter.type = .transfer }
                Menu {
                    Button("Todas las cuentas") { vm.filter.accountId = nil }
                    ForEach(vm.accounts) { a in Button(a.name) { vm.filter.accountId = a.id } }
                } label: { chipLabel(vm.accounts.first { $0.id == vm.filter.accountId }?.name ?? "Cuenta", vm.filter.accountId != nil, menu: true) }
                Menu {
                    Button("Todas las categorías") { vm.filter.categoryId = nil }
                    ForEach(vm.categories.filter { $0.type == "expense" || $0.type == "income" }) { c in Button(c.name) { vm.filter.categoryId = c.id } }
                } label: { chipLabel(vm.categories.first { $0.id == vm.filter.categoryId }?.name ?? "Categoría", vm.filter.categoryId != nil, menu: true) }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, on, menu: false) }.buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chipLabel(_ title: String, _ on: Bool, menu: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            if menu { Image(systemName: "chevron.down").font(.caption2) }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14).frame(minHeight: 36)
        .background(on ? VexiaColor.brandFill : Color(.secondarySystemGroupedBackground), in: .capsule)
        .foregroundStyle(on ? .white : .primary)
        .overlay(Capsule().strokeBorder(on ? .clear : Color(.separator)))
    }

    private var summaryCard: some View {
        let t = vm.totals
        let total = max(t.income + t.expenses, 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                stat("Ingresos", Fmt.money(t.income, currency: t.currency, compact: true), VexiaColor.incomeText)
                stat("Gastos", Fmt.money(t.expenses, currency: t.currency, compact: true), VexiaColor.expenseText)
                let net = t.income - t.expenses
                stat("Neto", (net > 0 ? "+" : "") + Fmt.money(net, currency: t.currency, compact: true), .primary)
            }
            GeometryReader { g in
                HStack(spacing: 2) {
                    Capsule().fill(VexiaColor.brandGreen).frame(width: BarMetrics.width(g.size.width, t.income / total))
                    Capsule().fill(VexiaColor.expenseFill)
                }
            }
            .frame(height: 8)
            .opacity(t.income + t.expenses > 0 ? 1 : 0.25)
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(VexiaColor.textSecondary)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static let placeholder = Mappers.transaction(["id": 0, "amount": 100, "currency": "USD", "description": "Cargando movimiento", "date": "2026-01-01", "type": "expense", "categoryName": "Categoría"])
}
