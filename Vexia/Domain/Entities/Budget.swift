import Foundation

nonisolated struct Budget: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var description: String?
    var budgetType: String
    var period: String
    var startDate: Date?
    var endDate: Date?
    var totalTargetAmount: Double?
    var currencyId: String
    var status: String
    var aiGenerated: Bool
    var items: [BudgetItem]

    var periodTitle: String {
        ["weekly": String(localized: "Semanal"), "biweekly": String(localized: "Quincenal"), "monthly": String(localized: "Mensual"), "quarterly": String(localized: "Trimestral"),
         "yearly": String(localized: "Anual"), "custom": String(localized: "Personalizado")][period] ?? period.capitalized
    }
    var statusTitle: String {
        ["draft": String(localized: "Borrador"), "active": String(localized: "Activo"), "paused": String(localized: "Pausado"), "archived": String(localized: "Archivado"), "completed": String(localized: "Completado")][status] ?? status
    }
}

nonisolated struct BudgetItem: Identifiable, Hashable, Sendable {
    let id: String
    var itemType: String
    var categoryId: String?
    var investmentSymbol: String?
    var customName: String?
    var targetAmount: Double
    var currentAmount: Double
    var targetDirection: String
    var priority: Int
    var isActive: Bool
    var notes: String?
    var tier: String?
}

nonisolated struct BudgetItemProgress: Identifiable, Hashable, Sendable {
    var id: String { item.id }
    var item: BudgetItem
    var percentage: Double
    var status: String // on_track | warning | over | under | completed
    var categoryNames: [String]

    var label: String {
        item.customName ?? (categoryNames.isEmpty ? nil : categoryNames.joined(separator: ", "))
            ?? item.investmentSymbol ?? item.itemType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

nonisolated struct BudgetProgress: Hashable, Sendable {
    var budget: Budget
    var items: [BudgetItemProgress]
    var totalTarget: Double
    var totalActual: Double
    var variance: Double
    var complianceRate: Double
    var currencyCode: String
}

nonisolated struct BudgetSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    var snapshotDate: Date?
    var periodStart: Date?
    var periodEnd: Date?
    var totalTarget: Double
    var totalActual: Double
    var complianceRate: Double
    var aiAnalysis: String?
}

/// Assistant (budget agent) chat message. Widgets are kept as raw specs so unknown types degrade gracefully.
nonisolated struct ChatMessage: Identifiable, Hashable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    let id: UUID
    var role: Role
    var text: String
    var widgets: [WidgetSpec]
    var date: Date
    var isPending = false

    init(id: UUID = UUID(), role: Role, text: String, widgets: [WidgetSpec] = [], date: Date = .now, isPending: Bool = false) {
        self.id = id; self.role = role; self.text = text; self.widgets = widgets; self.date = date; self.isPending = isPending
    }
}

nonisolated struct WidgetSpec: Hashable, Sendable, Identifiable {
    var id: String { (interactionId ?? "") + type }
    var type: String
    var props: JSON
    var interactionId: String?
}

nonisolated struct AgentReply: Hashable, Sendable {
    var message: String
    var widgets: [WidgetSpec]
    var sessionId: String?
}
