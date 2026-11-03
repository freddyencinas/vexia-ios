import SwiftUI

/// Snippet shown by Siri after saving: same reading order as a Movimientos row.
struct SiriTransactionCard: View {
    let proposal: ProposeTransactionUseCase.Proposal

    var body: some View {
        HStack(spacing: 12) {
            if let category = proposal.category {
                CategoryIcon(category: category, size: 44)
            } else {
                IconBadge(symbol: "arrow.left.arrow.right", color: VexiaColor.info, size: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(SiriTransactionText.title(proposal)).font(.body.weight(.semibold)).lineLimit(1)
                Text(SiriTransactionText.detail(proposal)).font(.caption).foregroundStyle(VexiaColor.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(SiriTransactionText.amount(proposal))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(proposal.draft.type == .income ? VexiaColor.incomeText : .primary)
        }
        .padding()
    }
}

#Preview {
    SiriTransactionCard(proposal: .init(
        draft: TransactionDraft(type: .expense, amount: 10, description: "salteña", currencyCode: "BOB"),
        account: Account(id: "a", name: "Efectivo", type: .cash, currencyId: "bob", currencyCode: "BOB", initialBalance: 0, isFavorite: true),
        category: FinancialCategory(id: "c", code: "SNACK", name: "Snack Refrigerio", icon: "🥐", type: "expense", isGlobal: false),
        isTransaction: true, missing: [], notes: [], heard: "10 bolivianos salteña en efectivo"))
}
