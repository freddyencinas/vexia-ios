import SwiftUI

struct VexiaConfirmView: View {
    @State var vm: VexiaConfirmViewModel
    var onSaved: () -> Void
    var onEditAll: (TransactionDraft) -> Void
    var onRetry: () -> Void
    @State private var showCategoryPicker = false
    @State private var showNoteEditor = false
    @State private var showDatePicker = false
    @State private var noteText = ""
    @State private var showAmountEditor = false
    @State private var amountText = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(SavedBannerCenter.self) private var savedBanner: SavedBannerCenter?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if vm.showsHeard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles").font(.headline).foregroundStyle(.white)
                                .frame(width: 44, height: 44).background(VexiaColor.brandFill, in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Escuché").font(.subheadline).foregroundStyle(VexiaColor.textSecondary)
                                Text("“\(vm.heard)”").font(.body.weight(.semibold))
                            }
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
            .alert("Monto", isPresented: $showAmountEditor) {
                TextField("0", text: $amountText).keyboardType(.decimalPad)
                Button("Cancelar", role: .cancel) {}
                Button("Guardar") { vm.setAmount(amountText) }
            }
            .alert("Nota", isPresented: $showNoteEditor) {
                TextField("Descripción", text: $noteText)
                Button("Cancelar", role: .cancel) {}
                Button("Guardar") { vm.draft.description = noteText.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .sheet(isPresented: $showDatePicker) { DatePickerSheet(date: $vm.draft.date) }
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
            Button {
                amountText = vm.amountEditText
                showAmountEditor = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(vm.amountText).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Image(systemName: "pencil").font(.title3).foregroundStyle(VexiaColor.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Editar monto"))
            FlowChips {
                Button { showCategoryPicker = true } label: {
                    chip("Categoría", vm.category.map { c in [CategorySymbol.emoji(c.icon), c.name].compactMap { $0 }.joined(separator: " ") } ?? String(localized: "Elegir"),
                         warn: vm.category == nil && vm.draft.type != .transfer)
                }
                .buttonStyle(.plain)
                Menu {
                    Picker("Cuenta", selection: $vm.draft.accountId) {
                        ForEach(vm.accounts) { Text("\($0.name) · \($0.code)").tag(Optional($0.id)) }
                    }
                } label: { chip("Cuenta", vm.account?.name ?? String(localized: "Elegir"), warn: vm.account == nil) }
                Menu {
                    Button("Hoy") { vm.draft.date = .now }
                    Button("Ayer") { vm.draft.date = Calendar.current.date(byAdding: .day, value: -1, to: .now)! }
                    Button("Otra fecha…", systemImage: "calendar") { showDatePicker = true }
                } label: { chip("Fecha", Calendar.current.isDateInToday(vm.draft.date) ? String(localized: "Hoy")
                    : Calendar.current.isDateInYesterday(vm.draft.date) ? String(localized: "Ayer") : Fmt.shortDate(vm.draft.date), warn: false) }
                Button {
                    noteText = vm.draft.description
                    showNoteEditor = true
                } label: { chip("Nota", vm.draft.description.isEmpty ? String(localized: "Agregar") : vm.draft.description, warn: false) }
                .buttonStyle(.plain)
            }
            .onChange(of: vm.draft.accountId) { vm.syncCurrency() }
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 22))
    }

    private func chip(_ k: LocalizedStringKey, _ v: String, warn: Bool) -> some View {
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
                Text(vm.missing.isEmpty ? String(localized: "Confirmar \(vm.draft.type.title.lowercased())") : String(localized: "Falta: \(vm.missing.joined(separator: ", "))"))
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glassProminent).controlSize(.large)
            .disabled(!vm.missing.isEmpty || vm.isSaving)
            HStack(spacing: 8) {
                Button { dismiss(); onEditAll(vm.draft) } label: { Text("Editar todo").frame(maxWidth: .infinity) }
                Button { dismiss(); onRetry() } label: {
                    Text(vm.fromReceipt ? String(localized: "Escanear otro") : String(localized: "Volver a dictar")).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glass).controlSize(.large)
        }
        .padding(.horizontal).padding(.bottom, 8)
    }
}

