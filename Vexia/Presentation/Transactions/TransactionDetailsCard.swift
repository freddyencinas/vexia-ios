import SwiftUI

/// Date chips, note and the collapsible "more options" (recurrence + tags).
struct TransactionDetailsCard: View {
    @Bindable var vm: TransactionFormViewModel
    var focus: FocusState<TransactionFormView.Field?>.Binding
    var onShowDatePicker: () -> Void
    // periphery:ignore - pending: collapsible "more options" section
    @State private var showMoreOptions = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Fecha")
                Spacer()
                dateChip(String(localized: "Hoy"), Calendar.current.isDateInToday(vm.draft.date)) { vm.draft.date = .now }
                dateChip(String(localized: "Ayer"), Calendar.current.isDateInYesterday(vm.draft.date)) {
                    vm.draft.date = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
                }
                // Selected custom date reads as a chip with its own label ("28 oct") + calendar icon.
                dateChip(isOtherDate ? Fmt.shortDate(vm.draft.date) : String(localized: "Otra…"), isOtherDate,
                         systemImage: "calendar") { onShowDatePicker() }
                    .accessibilityLabel(isOtherDate ? Text("Fecha: \(Fmt.shortDate(vm.draft.date))") : Text("Elegir otra fecha"))
            }
            .frame(minHeight: 52)
            Divider()
            TextField(vm.draft.type == .transfer ? String(localized: "Descripción (opcional)") : String(localized: "Añadir nota (opcional)"), text: $vm.draft.description, axis: .vertical)
                .focused(focus, equals: .note)
                .frame(minHeight: 52)
            if vm.draft.type != .transfer {
                Divider()
                moreOptions
            }
        }
        .padding(.horizontal, 14)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    private var moreOptions: some View {
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

    private var isOtherDate: Bool { !Calendar.current.isDateInToday(vm.draft.date) && !Calendar.current.isDateInYesterday(vm.draft.date) }
    private var optionsSummary: String {
        var parts: [String] = []
        if vm.draft.isRecurring { parts.append(vm.draft.recurringFrequency.title) }
        if !vm.draft.tags.isEmpty { parts.append(vm.draft.tags.count == 1 ? String(localized: "1 etiqueta") : String(localized: "\(vm.draft.tags.count) etiquetas")) }
        return parts.isEmpty ? String(localized: "Recurrente · Etiquetas") : parts.joined(separator: " · ")
    }

    private func dateChip(_ title: String, _ on: Bool, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).font(.caption) }
                Text(title)
            }
            .font(.footnote.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 32)
                .background(on ? VexiaColor.brandFill : Color(.secondarySystemBackground), in: .capsule)
                .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
