import SwiftUI

/// Accent/case-insensitive category search ("cafe" finds "Café", "snack" finds "Snack").
nonisolated enum CategorySearch {
    static func filter(_ categories: [FinancialCategory], query: String) -> [FinancialCategory] {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return categories }
        return categories.filter { fold($0.name).contains(q) || fold($0.code).contains(q) }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

/// Emoji from the backend when present, SF Symbol fallback otherwise.
struct CategoryIcon: View {
    let category: FinancialCategory
    var size: CGFloat = 32

    var body: some View {
        IconBadge(symbol: CategorySymbol.of(icon: category.icon, name: category.name),
                  color: CategorySymbol.color(for: category.code.isEmpty ? category.name : category.code),
                  size: size, emoji: CategorySymbol.emoji(category.icon))
    }
}

/// Searchable category list; the user's own categories are listed first.
struct CategoryPickerSheet: View {
    let categories: [FinancialCategory]
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [FinancialCategory] { CategorySearch.filter(categories, query: query) }
    private var mine: [FinancialCategory] { results.filter { !$0.isGlobal } }
    private var general: [FinancialCategory] { results.filter(\.isGlobal) }

    var body: some View {
        NavigationStack {
            List {
                if !mine.isEmpty { Section("Mis categorías") { rows(mine) } }
                if !general.isEmpty { Section(mine.isEmpty ? "" : String(localized: "Generales")) { rows(general) } }
            }
            .overlay {
                if results.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar categoría")
            .navigationTitle("Categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar", systemImage: "xmark") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func rows(_ list: [FinancialCategory]) -> some View {
        ForEach(list) { c in
            Button {
                selection = c.id
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    CategoryIcon(category: c)
                    Text(c.name).foregroundStyle(.primary)
                    Spacer()
                    if selection == c.id { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(VexiaColor.brandBlue) }
                }
            }
            .accessibilityAddTraits(selection == c.id ? .isSelected : [])
        }
    }
}
