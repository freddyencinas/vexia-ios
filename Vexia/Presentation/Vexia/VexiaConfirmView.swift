import SwiftUI

/// One-tap confirmation of an AI-captured transaction (design: "Vexia: confirmar").
@Observable
final class VexiaConfirmViewModel {
    var draft: TransactionDraft
    let notes: [String]
    let heard: String
    private(set) var accounts: [Account] = []
    private(set) var categories: [FinancialCategory] = []
    private(set) var isSaving = false
    var errorMessage: String?
    private let save: SaveTransactionUseCase
    private let catalog: CatalogRepository

    init(draft: TransactionDraft, notes: [String], heard: String, save: SaveTransactionUseCase, catalog: CatalogRepository) {
        self.draft = draft; self.notes = notes; self.heard = heard; self.save = save; self.catalog = catalog
    }

    func load() async {
        async let a = try? catalog.accounts()
        async let c = try? catalog.categories(type: nil)
        accounts = await a ?? []
        categories = await c ?? []
        syncCurrency()
    }

    var account: Account? { accounts.first { $0.id == draft.accountId } }
    var category: FinancialCategory? { categories.first { $0.id == draft.categoryId } }
    var typeCategories: [FinancialCategory] { categories.filter { $0.type == draft.type.rawValue } }
    var missing: [String] {
        var m: [String] = []
        if draft.amount <= 0 { m.append("monto") }
        if account == nil { m.append("cuenta") }
        if draft.type != .transfer && category == nil { m.append("categoría") }
        return m
    }
    var amountText: String { Fmt.money(draft.amount, currency: account?.code ?? draft.currencyCode.nilIfEmpty ?? "USD") }

    func syncCurrency() {
        if let a = account { draft.currency = a.currencyId; draft.currencyCode = a.code.uppercased() }
    }

    func confirm() async -> Bool {
        syncCurrency()
        isSaving = true; defer { isSaving = false }
        do { try await save(draft); return true } catch { errorMessage = error.localizedDescription; return false }
    }
}

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

struct VexiaConfirmView: View {
    @State var vm: VexiaConfirmViewModel
    var onSaved: () -> Void
    var onEditAll: (TransactionDraft) -> Void
    var onRetry: () -> Void
    @State private var showCategoryPicker = false
    @State private var showNoteEditor = false
    @State private var noteText = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(SavedBannerCenter.self) private var savedBanner: SavedBannerCenter?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles").font(.headline).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(VexiaColor.brandFill, in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Escuché").font(.subheadline).foregroundStyle(VexiaColor.textSecondary)
                            Text("“\(vm.heard)”").font(.body.weight(.semibold))
                        }
                    }
                    card
                    if !vm.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(vm.notes, id: \.self) { Label($0, systemImage: "info.circle").font(.footnote) }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(VexiaColor.amberSoft, in: .rect(cornerRadius: 12)).foregroundStyle(VexiaColor.warningText)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle("Confirmar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar", systemImage: "xmark") { dismiss() } } }
            .task { await vm.load() }
            .alert("Nota", isPresented: $showNoteEditor) {
                TextField("Descripción", text: $noteText)
                Button("Cancelar", role: .cancel) {}
                Button("Guardar") { vm.draft.description = noteText.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerSheet(categories: vm.typeCategories, selection: $vm.draft.categoryId)
            }
            .errorAlert($vm.errorMessage)
        }
        .presentationDetents([.height(660), .large])
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(vm.draft.type.title.uppercased()).font(.caption.weight(.bold))
                    .foregroundStyle(vm.draft.type == .income ? VexiaColor.incomeText : VexiaColor.expenseText)
                Spacer()
                Text("Toca un dato para cambiarlo").font(.caption).foregroundStyle(VexiaColor.textSecondary)
            }
            Text(vm.amountText).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
            FlowChips {
                Button { showCategoryPicker = true } label: {
                    chip("Categoría", vm.category.map { c in [CategorySymbol.emoji(c.icon), c.name].compactMap { $0 }.joined(separator: " ") } ?? "Elegir",
                         warn: vm.category == nil && vm.draft.type != .transfer)
                }
                .buttonStyle(.plain)
                Menu {
                    Picker("Cuenta", selection: $vm.draft.accountId) {
                        ForEach(vm.accounts) { Text("\($0.name) · \($0.code)").tag(Optional($0.id)) }
                    }
                } label: { chip("Cuenta", vm.account?.name ?? "Elegir", warn: vm.account == nil) }
                Menu {
                    Button("Hoy") { vm.draft.date = .now }
                    Button("Ayer") { vm.draft.date = Calendar.current.date(byAdding: .day, value: -1, to: .now)! }
                } label: { chip("Fecha", Calendar.current.isDateInToday(vm.draft.date) ? "Hoy" : Fmt.shortDate(vm.draft.date), warn: false) }
                Button {
                    noteText = vm.draft.description
                    showNoteEditor = true
                } label: { chip("Nota", vm.draft.description.isEmpty ? "Agregar" : vm.draft.description, warn: false) }
                .buttonStyle(.plain)
            }
            .onChange(of: vm.draft.accountId) { vm.syncCurrency() }
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 22))
    }

    private func chip(_ k: String, _ v: String, warn: Bool) -> some View {
        HStack(spacing: 6) {
            Text(k).foregroundStyle(VexiaColor.textSecondary)
            Text(v).fontWeight(.semibold).foregroundStyle(.primary)
            if warn { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(VexiaColor.warning) }
        }
        .font(.subheadline)
        .padding(.horizontal, 12).frame(minHeight: 36)
        .background(warn ? VexiaColor.amberSoft : Color(.secondarySystemBackground), in: .capsule)
        .overlay(Capsule().strokeBorder(warn ? VexiaColor.warning : Color(.separator), lineWidth: 1))
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    if await vm.confirm() {
                        savedBanner?.announce(SavedBanner.summary(type: vm.draft.type, isEditing: false, isExchange: false,
                                                          amount: vm.amountText, account: vm.account?.name))
                        onSaved(); dismiss()
                    }
                }
            } label: {
                Text(vm.missing.isEmpty ? "Confirmar \(vm.draft.type.title.lowercased())" : "Falta: \(vm.missing.joined(separator: ", "))")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glassProminent).controlSize(.large)
            .disabled(!vm.missing.isEmpty || vm.isSaving)
            HStack(spacing: 8) {
                Button { dismiss(); onEditAll(vm.draft) } label: { Text("Editar todo").frame(maxWidth: .infinity) }
                Button { dismiss(); onRetry() } label: { Text("Volver a dictar").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.glass).controlSize(.large)
        }
        .padding(.horizontal).padding(.bottom, 8)
    }
}

/// Simple wrapping layout for chips.
struct FlowChips: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
