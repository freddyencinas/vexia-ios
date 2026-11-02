import SwiftUI

@Observable
final class BudgetsHubViewModel {
    private(set) var state: Loadable<[Budget]> = .idle
    var errorMessage: String?
    let repo: BudgetRepository
    init(repo: BudgetRepository) { self.repo = repo }

    var active: [Budget] { state.value?.filter { $0.status == "active" } ?? [] }
    var others: [Budget] { state.value?.filter { $0.status != "active" } ?? [] }

    func load() async {
        if state.value == nil { state = .loading }
        do { state = .loaded(try await repo.budgets()) } catch { state = .failed(error.localizedDescription) }
    }

    func delete(_ b: Budget) async {
        do { try await repo.delete(budgetId: b.id); await load() } catch { errorMessage = error.localizedDescription }
    }
}

@Observable
final class BudgetProgressViewModel {
    let budgetId: String
    private(set) var state: Loadable<BudgetProgress> = .idle
    private(set) var snapshots: [BudgetSnapshot] = []
    var editingItem: BudgetItemProgress?
    var editTargetText = ""
    var errorMessage: String?
    private let repo: BudgetRepository

    init(budgetId: String, repo: BudgetRepository) { self.budgetId = budgetId; self.repo = repo }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            async let p = repo.progress(budgetId: budgetId)
            async let s = try? repo.snapshots(budgetId: budgetId)
            state = .loaded(try await p)
            snapshots = await s ?? []
        } catch { state = .failed(error.localizedDescription) }
    }

    func beginEdit(_ item: BudgetItemProgress) {
        editingItem = item
        editTargetText = Fmt.editable(item.item.targetAmount, digits: 0...2)
    }

    func saveEdit() async {
        guard let item = editingItem, let v = Double(editTargetText.replacingOccurrences(of: ",", with: ".")), v >= 0 else { return }
        editingItem = nil
        do { try await repo.updateItemTarget(budgetId: budgetId, itemId: item.id, target: v); await load() }
        catch { errorMessage = error.localizedDescription }
    }

    func takeSnapshot() async {
        do { try await repo.createSnapshot(budgetId: budgetId); await load() } catch { errorMessage = error.localizedDescription }
    }

    func deleteSnapshot(_ s: BudgetSnapshot) async {
        do { try await repo.deleteSnapshot(budgetId: budgetId, snapshotId: s.id); snapshots.removeAll { $0.id == s.id } }
        catch { errorMessage = error.localizedDescription }
    }
}

/// Budget-planner AI chat. Talks to the `BudgetAgent` port only.
/// Chat state persisted locally (text only).
@Observable
final class AssistantChatViewModel {
    private(set) var messages: [ChatMessage] = []
    var input = ""
    private(set) var isSending = false
    private var sessionId: String?
    private let agent: BudgetAgent
    private let context: () -> AgentContext

    static var suggestions: [String] { [String(localized: "Ayúdame a crear un presupuesto mensual"), String(localized: "¿En qué gasto más?"),
                              String(localized: "¿Cuánto puedo ahorrar este mes?"), String(localized: "Analiza mis últimos 3 meses")] }

    init(agent: BudgetAgent, context: @escaping () -> AgentContext) {
        self.agent = agent; self.context = context
        restore()
    }

    func send(_ text: String? = nil) async {
        let message = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSending else { return }
        input = ""
        messages.append(ChatMessage(role: .user, text: message))
        let pending = ChatMessage(role: .assistant, text: "", isPending: true)
        messages.append(pending)
        isSending = true; defer { isSending = false }
        do {
            if sessionId == nil { sessionId = "sess_\(Int(Date.now.timeIntervalSince1970 * 1000))" }
            let reply = try await agent.send(message: message, sessionId: sessionId, context: context())
            apply(reply, replacing: pending.id)
        } catch {
            replace(pending.id, with: ChatMessage(role: .assistant, text: "⚠️ \(error.localizedDescription)"))
        }
        persist()
    }

    func interact(_ widget: WidgetSpec, value: JSON) async {
        guard let sessionId, let iid = widget.interactionId, !isSending else { return }
        let pending = ChatMessage(role: .assistant, text: "", isPending: true)
        messages.append(pending)
        isSending = true; defer { isSending = false }
        do {
            let reply = try await agent.interact(sessionId: sessionId, interactionId: iid, value: value, widgetType: widget.type, context: context())
            apply(reply, replacing: pending.id)
        } catch {
            replace(pending.id, with: ChatMessage(role: .assistant, text: "⚠️ \(error.localizedDescription)"))
        }
        persist()
    }

    func reset() async {
        if let sessionId { await agent.endSession(sessionId) }
        sessionId = nil
        messages = []
        persist()
    }

    private func apply(_ reply: AgentReply, replacing id: UUID) {
        if let s = reply.sessionId { sessionId = s }
        replace(id, with: ChatMessage(role: .assistant, text: reply.message, widgets: reply.widgets))
    }

    private func replace(_ id: UUID, with m: ChatMessage) {
        if let i = messages.firstIndex(where: { $0.id == id }) { messages[i] = m } else { messages.append(m) }
    }

    private let storeKey = "budget_planner_chat_state_ios_v1"
    private func persist() {
        let arr: [[String: String]] = messages.filter { !$0.isPending }.suffix(50).map { ["role": $0.role.rawValue, "text": $0.text] }
        UserDefaults.standard.set(["sessionId": sessionId ?? "", "messages": arr] as [String: Any], forKey: storeKey)
    }
    private func restore() {
        guard let d = UserDefaults.standard.dictionary(forKey: storeKey) else { return }
        sessionId = (d["sessionId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        messages = (d["messages"] as? [[String: String]] ?? []).map {
            ChatMessage(role: ChatMessage.Role(rawValue: $0["role"] ?? "") ?? .assistant, text: $0["text"] ?? "")
        }
    }
}
