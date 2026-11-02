import SwiftUI

struct BudgetsHubView: View {
    @State var vm: BudgetsHubViewModel
    var month: DashboardViewModel.MonthTotals?
    var openAssistant: (String?) -> Void

    private struct Template: Identifiable { let id: String; let title: String; let desc: String; let slices: [(Color, Double)]; let prompt: String }
    private let templates: [Template] = [
        .init(id: "50/30/20", title: "50/30/20", desc: String(localized: "Necesidades 50% · Gustos 30% · Ahorro 20%"),
              slices: [(VexiaColor.brandBlue, 0.5), (VexiaColor.brandGreen, 0.3), (VexiaColor.warning, 0.2)],
              prompt: "Crea un presupuesto mensual 50/30/20 con mis ingresos y gastos reales"),
        .init(id: "savings-first", title: String(localized: "Ahorro primero"), desc: String(localized: "Separa el 30% al cobrar y gasta el resto"),
              slices: [(VexiaColor.brandGreen, 0.3), (VexiaColor.blueMuted, 0.7)],
              prompt: "Crea un presupuesto que separe primero el 30% de mis ingresos para ahorro"),
        .init(id: "by-category", title: String(localized: "Por categoría"), desc: String(localized: "Pon un tope a cada gasto, como Alimentación o Transporte"),
              slices: [(VexiaColor.brandBlue, 0.25), (VexiaColor.brandGreen, 0.2), (VexiaColor.warning, 0.25), (Color(hex: 0xB0306A), 0.3)],
              prompt: "Crea un presupuesto con un tope por categoría según mis gastos de los últimos meses"),
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(month == nil ? String(localized: "PLANIFICA CON IA") : String(localized: "CON TUS DATOS DE \(month!.label.uppercased())"))
                        .font(.caption.weight(.semibold)).foregroundStyle(Color(hex: 0xCDEFE2))
                    Text(month.map { String(localized: "En \($0.label.lowercased()) llevas \(Fmt.money($0.expenses, currency: $0.currency)) en gastos. Vexia puede armar tu presupuesto en un minuto.") }
                         ?? String(localized: "Vexia analiza tus movimientos y te propone un presupuesto."))
                        .font(.title3.weight(.bold)).foregroundStyle(.white)
                    Button("Crear con Vexia") { openAssistant("Ayúdame a crear un presupuesto mensual con mis gastos reales") }
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(.white, in: .capsule).foregroundStyle(Color(hex: 0x15307C))
                        .buttonStyle(.plain)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(VexiaColor.brandFill, in: .rect(cornerRadius: 22))
                .listRowInsets(.init()).listRowBackground(Color.clear)
            }
            LoadableSection(state: vm.state, retry: { Task { await vm.load() } }) { _ in
                if !vm.active.isEmpty { Section("Activos") { rows(vm.active) } }
                if !vm.others.isEmpty { Section("Otros") { rows(vm.others) } }
                if vm.active.isEmpty && vm.others.isEmpty {
                    Section("O empieza con una plantilla") {
                        ForEach(templates) { t in
                            Button { openAssistant(t.prompt) } label: {
                                HStack(spacing: 12) {
                                    DonutSlices(slices: t.slices).frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(t.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                        Text(t.desc).font(.footnote).foregroundStyle(VexiaColor.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .navigationDestination(for: Budget.self) { b in
            BudgetProgressView(vm: BudgetProgressViewModel(budgetId: b.id, repo: vm.repo), title: b.name)
        }
        .errorAlert($vm.errorMessage)
    }

    private func rows(_ budgets: [Budget]) -> some View {
        ForEach(budgets) { b in
            NavigationLink(value: b) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(b.name).font(.headline)
                        if b.aiGenerated { Image(systemName: "sparkles").font(.caption).foregroundStyle(VexiaColor.violet) }
                    }
                    Text("\(b.periodTitle) · \(b.items.count) partidas · \(b.statusTitle)")
                        .font(.footnote).foregroundStyle(VexiaColor.textSecondary)
                    if let t = b.totalTargetAmount { Text("Meta \(Fmt.grouped(t))").font(.footnote.monospacedDigit()) }
                }
            }
            .swipeActions { Button(role: .destructive) { Task { await vm.delete(b) } } label: { Label("Eliminar", systemImage: "trash") } }
        }
    }
}

/// Tiny donut used by budget templates.
struct DonutSlices: View {
    let slices: [(Color, Double)]
    var body: some View {
        ZStack {
            ForEach(Array(slices.enumerated()), id: \.offset) { i, s in
                let start = slices.prefix(i).reduce(0) { $0 + $1.1 }
                Circle().trim(from: start, to: start + s.1).stroke(s.0, lineWidth: 10).rotationEffect(.degrees(-90))
            }
        }
        .padding(5)
        .accessibilityHidden(true)
    }
}

/// Section-level Loadable switch for Lists.
struct LoadableSection<V, Content: View>: View {
    let state: Loadable<V>
    var retry: () -> Void
    @ViewBuilder var content: (V) -> Content
    var body: some View {
        switch state {
        case .idle, .loading: ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
        case .failed(let m):
            ContentUnavailableView { Label("Error", systemImage: "exclamationmark.triangle") }
                description: { Text(m) } actions: { Button("Reintentar", action: retry).buttonStyle(.glass) }
        case .loaded(let v): content(v)
        }
    }
}

struct BudgetProgressView: View {
    @State var vm: BudgetProgressViewModel
    let title: String

    var body: some View {
        List {
            LoadableSection(state: vm.state, retry: { Task { await vm.load() } }) { p in
                Section { summary(p).listRowBackground(Color.clear).listRowInsets(.init()) }
                Section("Partidas") {
                    ForEach(p.items) { item in
                        Button { vm.beginEdit(item) } label: { itemRow(item, currency: p.currencyCode) }.buttonStyle(.plain)
                    }
                }
                Section {
                    ForEach(vm.snapshots) { s in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(s.periodStart.map(Fmt.monthYear) ?? String(localized: "Snapshot")).font(.subheadline.weight(.medium))
                                Text("Real \(Fmt.money(s.totalActual, currency: p.currencyCode)) / Meta \(Fmt.money(s.totalTarget, currency: p.currencyCode))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Fmt.percent(s.complianceRate)).font(.subheadline.bold().monospacedDigit())
                        }
                        .swipeActions { Button(role: .destructive) { Task { await vm.deleteSnapshot(s) } } label: { Label("Eliminar", systemImage: "trash") } }
                    }
                    if vm.snapshots.isEmpty { Text("Sin snapshots").foregroundStyle(.secondary) }
                } header: {
                    HStack { Text("Historial"); Spacer(); Button("Crear snapshot", systemImage: "camera") { Task { await vm.takeSnapshot() } }.font(.caption) }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .alert("Editar meta", isPresented: Binding(get: { vm.editingItem != nil }, set: { if !$0 { vm.editingItem = nil } })) {
            TextField("Monto", text: $vm.editTargetText).keyboardType(.decimalPad)
            Button("Guardar") { Task { await vm.saveEdit() } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text(vm.editingItem?.label ?? "") }
        .errorAlert($vm.errorMessage)
    }

    private func summary(_ p: BudgetProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ejecutado").font(.caption).foregroundStyle(.white.opacity(0.8))
                    Text(Fmt.money(p.totalActual, currency: p.currencyCode)).font(.title.bold().monospacedDigit())
                    Text("de \(Fmt.money(p.totalTarget, currency: p.currencyCode))").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Gauge(value: min(p.complianceRate, 100), in: 0...100) { Text(verbatim: "") } currentValueLabel: {
                    Text(Fmt.percent(p.complianceRate)).font(.caption.bold())
                }
                .gaugeStyle(.accessoryCircularCapacity).tint(.white).scaleEffect(1.3)
            }
            Text("Cumplimiento \(p.budget.periodTitle.lowercased())").font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white).padding(20)
        .background(VexiaColor.heroGradient, in: .rect(cornerRadius: 24))
    }

    private func itemRow(_ i: BudgetItemProgress, currency: String) -> some View {
        let color: Color = switch i.status { case "over": VexiaColor.error; case "warning": VexiaColor.warning; case "completed": VexiaColor.success; default: VexiaColor.brandBlue }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(i.label).font(.subheadline.weight(.medium)).lineLimit(1)
                if let tier = i.item.tier { Text(tier).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: .capsule) }
                Spacer()
                Text("\(Fmt.money(i.item.currentAmount, currency: currency)) / \(Fmt.money(i.item.targetAmount, currency: currency))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: min(i.percentage, 100), total: 100).tint(color)
        }
        .padding(.vertical, 4)
    }
}
