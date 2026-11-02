import SwiftUI

struct AssistantChatView: View {
    @State var vm: AssistantChatViewModel
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if vm.messages.isEmpty { welcome }
                    ForEach(vm.messages) { m in
                        MessageBubble(message: m) { w, v in Task { await vm.interact(w, value: v) } }.id(m.id)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { withAnimation { proxy.scrollTo(vm.messages.last?.id, anchor: .bottom) } }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle("Vexia IA")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Nueva conversación", systemImage: "square.and.pencil") { Task { await vm.reset() } }
                    .disabled(vm.messages.isEmpty)
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(VexiaColor.accentGradient)
            Text("Hola, soy Vexia").font(.title2.bold())
            Text("Puedo analizar tus gastos, proponerte un presupuesto y ayudarte a cumplir tus metas.")
                .foregroundStyle(.secondary)
            ForEach(AssistantChatViewModel.suggestions, id: \.self) { s in
                Button { Task { await vm.send(s) } } label: {
                    Text(s).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.top, 24)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Escribe un mensaje…", text: $vm.input, axis: .vertical)
                .lineLimit(1...5).focused($focused)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .onSubmit { Task { await vm.send() } }
            Button { Task { await vm.send() } } label: {
                Image(systemName: vm.isSending ? "ellipsis" : "arrow.up").font(.headline)
                    .symbolEffect(.variableColor.iterative, isActive: vm.isSending)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glassProminent).buttonBorderShape(.circle)
            .disabled(vm.input.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSending)
            .accessibilityLabel("Enviar")
        }
        .padding(.horizontal).padding(.vertical, 8)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var onInteract: (WidgetSpec, JSON) -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if message.isPending {
                    HStack(spacing: 8) { ProgressView(); Text("Vexia está pensando…").font(.subheadline).foregroundStyle(.secondary) }
                        .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 18))
                } else if !message.text.isEmpty {
                    Text(LocalizedStringKey(message.text)) // renders inline Markdown
                        .textSelection(.enabled)
                        .padding(12)
                        .foregroundStyle(message.role == .user ? .white : .primary)
                        .background {
                            if message.role == .user { RoundedRectangle(cornerRadius: 18).fill(VexiaColor.brandFill) }
                        }
                        .glassEffect(message.role == .user ? .identity : .regular, in: .rect(cornerRadius: 18))
                }
                ForEach(message.widgets) { w in AgentWidgetView(spec: w, onInteract: onInteract) }
            }
            if message.role == .assistant { Spacer(minLength: 24) }
        }
    }
}

/// Generic renderer for A2UI widget specs. Known simple types get native UI; complex ones
/// (proposal/setup cards) degrade to a summary card.
struct AgentWidgetView: View {
    let spec: WidgetSpec
    var onInteract: (WidgetSpec, JSON) -> Void

    var body: some View {
        let p = spec.props
        switch spec.type {
        case "ActionButton":
            Button(p["label"].string ?? String(localized: "Acción")) { onInteract(spec, ["action": p["action"]]) }
                .buttonStyle(.glassProminent).disabled(spec.interactionId == nil)
        case "BudgetItemCard", "SavingsProgressBar", "CategoryBudgetSlider", "InvestmentTargetCard":
            let current = p.first("current", "currentAmount", "value").doubleValue
            let target = p.first("target", "targetAmount", "max").doubleValue
            card {
                Text(p.first("label", "title", "categoryName", "symbol").string ?? spec.type).font(.subheadline.weight(.semibold))
                if target > 0 {
                    ProgressView(value: min(current, target), total: target)
                    Text("\(Fmt.money(current, currency: p["currency"].string ?? "USD")) / \(Fmt.money(target, currency: p["currency"].string ?? "USD"))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        default:
            card {
                Label(p.first("title", "label").string ?? humanize(spec.type), systemImage: "rectangle.stack")
                    .font(.subheadline.weight(.semibold))
                if let s = p.first("subtitle", "description", "message").string { Text(s).font(.caption).foregroundStyle(.secondary) }
                ForEach(numericProps(p), id: \.0) { k, v in
                    LabeledContent(humanize(k), value: Fmt.number(v)).font(.caption)
                }
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6, content: c)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func numericProps(_ p: JSON) -> [(String, Double)] {
        p.object.compactMap { k, v in if case .number(let n) = v { (k, n) } else { nil } }.sorted { $0.0 < $1.0 }.prefix(6).map { $0 }
    }

    private func humanize(_ s: String) -> String {
        s.replacingOccurrences(of: #"([a-z])([A-Z])"#, with: "$1 $2", options: .regularExpression).capitalized
    }
}
