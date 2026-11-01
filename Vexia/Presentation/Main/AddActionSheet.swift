import SwiftUI

/// Single entry point for capturing data (design review P0: one "+" instead of accessory + 2 AI entries).
struct AddActionSheet: View {
    enum Action: Hashable { case manual, voice, receipt, assistant, investment }
    var investmentsFirst: Bool
    var onPick: (Action) -> Void
    @Environment(\.dismiss) private var dismiss

    private struct Item: Identifiable {
        let id: Action; let title: String; let subtitle: String; let symbol: String; let tint: Color; let soft: Color
    }

    private var items: [Item] {
        var list: [Item] = [
            .init(id: .manual, title: "Gasto o ingreso", subtitle: "Escríbelo tú, en segundos", symbol: "square.and.pencil", tint: VexiaColor.brandBlue, soft: VexiaColor.tintSoft),
            .init(id: .voice, title: "Dictar con voz", subtitle: "“Gasté 50 en almuerzo”", symbol: "mic.fill", tint: VexiaColor.brandGreen, soft: VexiaColor.greenSoft),
            .init(id: .receipt, title: "Escanear recibo", subtitle: "Foto o imagen de la galería", symbol: "doc.text.viewfinder", tint: VexiaColor.cautionText, soft: VexiaColor.amberSoft),
            .init(id: .assistant, title: "Preguntar a Vexia", subtitle: "Presupuesto, análisis y metas", symbol: "sparkles", tint: VexiaColor.violet, soft: VexiaColor.violetSoft),
        ]
        if investmentsFirst {
            list.insert(.init(id: .investment, title: "Compra o venta", subtitle: "Acciones o cripto", symbol: "chart.line.uptrend.xyaxis", tint: VexiaColor.brandBlue, soft: VexiaColor.tintSoft), at: 0)
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    dismiss()
                    onPick(item.id)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: item.symbol).font(.title3.weight(.semibold)).foregroundStyle(item.tint)
                            .frame(width: 44, height: 44).background(item.soft, in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text(item.subtitle).font(.subheadline).foregroundStyle(VexiaColor.textSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Añadir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar", systemImage: "xmark") { dismiss() } } }
        }
        .presentationDetents([.height(investmentsFirst ? 470 : 400), .large])
    }
}
