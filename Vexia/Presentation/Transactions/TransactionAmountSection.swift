import SwiftUI

/// Account picker capsule shared by the amount header and the transfer cards.
struct TransactionAccountMenu: View {
    @Bindable var vm: TransactionFormViewModel
    let selection: Binding<String?>
    let label: String
    var exclude: String?

    var body: some View {
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

struct TransactionTypePicker: View {
    @Bindable var vm: TransactionFormViewModel

    var body: some View {
        Picker("Tipo", selection: $vm.draft.type) {
            ForEach(TransactionType.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .disabled(vm.isEditing && vm.draft.type == .transfer)
        .onChange(of: vm.draft.type) { vm.typeChanged(); Task { await vm.accountsChanged() } }
    }
}

/// Big amount input for income/expense.
struct TransactionAmountHeader: View {
    @Bindable var vm: TransactionFormViewModel
    var focus: FocusState<TransactionFormView.Field?>.Binding

    var body: some View {
        VStack(spacing: 8) {
            TransactionAccountMenu(vm: vm, selection: $vm.draft.accountId, label: vm.fromAccount.map { "\($0.name) · \(Fmt.symbol($0.code) ?? $0.code)" } ?? String(localized: "Elegir cuenta"))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.symbol(vm.accountCode) ?? vm.accountCode).font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(VexiaColor.textSecondary)
                TextField("0", text: $vm.amountText)
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(vm.draft.type == .income ? VexiaColor.incomeText : .primary)
                    .keyboardType(.decimalPad).fixedSize().focused(focus, equals: .amount)
                    .onChange(of: vm.amountText) { if focus.wrappedValue == .amount { vm.amountChanged() } }
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
}

/// From/to account cards with swap button for transfers.
struct TransactionExchangeCards: View {
    @Bindable var vm: TransactionFormViewModel
    var focus: FocusState<TransactionFormView.Field?>.Binding

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                VStack(spacing: 6) {
                    sideCard(title: "Envías desde", account: vm.fromAccount, selection: $vm.draft.accountId) {
                        TextField("0", text: $vm.amountText)
                            .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                            .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                            .focused(focus, equals: .amount)
                            .onChange(of: vm.amountText) { if focus.wrappedValue == .amount { vm.amountChanged() } }
                            .accessibilityLabel("Monto que envías")
                    }
                    sideCard(title: "Recibes en", account: vm.toAccount, selection: $vm.draft.toAccountId, exclude: vm.draft.accountId) {
                        if vm.needsConversion {
                            TextField("0", text: $vm.toAmountText)
                                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(VexiaColor.incomeText)
                                .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                                .focused(focus, equals: .toAmount)
                                .onChange(of: vm.toAmountText) { if focus.wrappedValue == .toAmount { vm.userEditedToAmount() } }
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

    private func sideCard<Amount: View>(title: LocalizedStringKey, account: Account?, selection: Binding<String?>, exclude: String? = nil,
                                        @ViewBuilder amount: () -> Amount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                if let a = account { Text("Saldo \(Fmt.money(a.balance, currency: a.code))") }
            }
            .font(.footnote).foregroundStyle(VexiaColor.textSecondary)
            HStack {
                TransactionAccountMenu(vm: vm, selection: selection, label: account.map { "\($0.name) · \(Fmt.symbol($0.code) ?? $0.code)" } ?? String(localized: "Elegir cuenta"), exclude: exclude)
                Spacer()
                amount()
            }
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 22))
    }
}
