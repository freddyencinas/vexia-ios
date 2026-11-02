import SwiftUI

/// Create/edit transaction (design: "Nueva transacción", "Gasto en otra moneda", "Cambio de divisa").
struct TransactionFormView: View {
    @State var vm: TransactionFormViewModel
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(SavedBannerCenter.self) private var savedBanner: SavedBannerCenter?
    @FocusState private var focus: Field?
    @State private var showDatePicker = false
    @State private var showCategoryPicker = false
    enum Field { case amount, toAmount, rate, note }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !vm.aiNotes.isEmpty { TransactionAINotes(notes: vm.aiNotes) }
                    TransactionTypePicker(vm: vm)
                    if vm.draft.type == .transfer { TransactionExchangeCards(vm: vm, focus: $focus) } else { TransactionAmountHeader(vm: vm, focus: $focus) }
                    if vm.showsRateCard { TransactionRateCard(vm: vm) }
                    if vm.needsConversion { TransactionFXRateCard(vm: vm, focus: $focus) }
                    if vm.draft.type != .transfer { TransactionCategoryGrid(vm: vm) { showCategoryPicker = true } }
                    TransactionDetailsCard(vm: vm, focus: $focus) { showDatePicker = true }
                    if vm.isEditing && !vm.originalSnapshots.isEmpty { TransactionSnapshotsCard(snapshots: vm.originalSnapshots) }
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
            .sheet(isPresented: $showDatePicker) { DatePickerSheet(date: $vm.draft.date) }
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerSheet(categories: vm.filteredCategories, selection: $vm.draft.categoryId)
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

    private var cta: some View {
        Button {
            Task { if await vm.submit() { savedBanner?.announce(vm.savedSummary); onSaved(); dismiss() } }
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
}
