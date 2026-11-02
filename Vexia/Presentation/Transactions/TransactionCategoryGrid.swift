import SwiftUI

struct TransactionCategoryGrid: View {
    @Bindable var vm: TransactionFormViewModel
    var onShowPicker: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Categoría").font(.subheadline.weight(.semibold))
                Spacer()
                if !vm.aiNotes.isEmpty {
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
                Button(action: onShowPicker) {
                    VStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(VexiaColor.textSecondary)
                        Text("Más").font(.caption2.weight(.semibold)).foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Buscar categoría")
            }
        }
        .padding(12)
        .background(.background, in: .rect(cornerRadius: 20))
    }
}
