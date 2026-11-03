import AppIntents
import SwiftUI

/// App shell — native iOS 27 TabView with Liquid Glass tab bar.
/// Design review: the prominent tab is a single "+" that opens `AddActionSheet`
/// (manual, voice, receipt, Vexia chat). No bottom accessory.
struct MainTabView: View {
    let container: AppContainer
    @Environment(SessionViewModel.self) private var session
    @Environment(IntentRouter.self) private var intents
    @State private var selection: AppTab = .dashboard
    @State private var lastTab: AppTab = .dashboard
    @State private var dashboardVM: DashboardViewModel
    @State private var transactionsVM: TransactionsListViewModel
    @State private var investmentsVM: InvestmentsViewModel
    @State private var budgetsVM: BudgetsHubViewModel
    @State private var chatVM: AssistantChatViewModel

    @State private var showAdd = false
    @State private var newTransaction: FormRequest?
    @State private var capture: VexiaCaptureView.Mode?
    @State private var confirm: ConfirmRequest?
    @State private var showAssistant = false
    @State private var showSettings = false
    @State private var showNewInvestment = false
    @State private var showRates = false
    @State private var savedBanner = SavedBannerCenter()
    @State private var island = ActivityIslandCenter()

    enum AppTab: Hashable { case dashboard, transactions, investments, budgets, add }

    struct FormRequest: Identifiable { let id = UUID(); var draft: TransactionDraft?; var notes: [String] = [] }
    struct ConfirmRequest: Identifiable { let id = UUID(); var draft: TransactionDraft; var notes: [String]; var heard: String }

    init(container: AppContainer, session: SessionViewModel) {
        self.container = container
        _dashboardVM = State(initialValue: DashboardViewModel(loadDashboard: container.loadDashboard, catalog: container.catalog, transactions: container.transactions))
        _transactionsVM = State(initialValue: TransactionsListViewModel(repo: container.transactions, catalog: container.catalog, delete: container.deleteTransaction))
        _investmentsVM = State(initialValue: InvestmentsViewModel(stocks: container.investments, crypto: container.crypto, catalog: container.catalog))
        _budgetsVM = State(initialValue: BudgetsHubViewModel(repo: container.budgets))
        let settings = container.settings
        _chatVM = State(initialValue: AssistantChatViewModel(agent: container.budgetAgent) { [weak session] in
            AgentContext(userCurrency: "USD", locale: settings.language, userName: session?.user?.firstName)
        })
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Inicio", systemImage: "house", value: .dashboard) {
                NavigationStack {
                    DashboardView(vm: dashboardVM, container: container,
                                  openAssistant: { message in openAssistant(message) },
                                  openBudgets: { selection = .budgets })
                        .toolbar { profileToolbar }
                        // Same screen the dashboard rates row pushes; opened from Siri ("abre tasas").
                        .navigationDestination(isPresented: $showRates) { RatesView(vm: RatesViewModel(catalog: container.catalog)) }
                }
            }
            Tab("Movimientos", systemImage: "list.bullet.rectangle", value: .transactions) {
                NavigationStack {
                    TransactionsView(vm: transactionsVM) { tx in makeForm(editing: tx) }
                        .navigationTitle("Movimientos")
                        .toolbar { profileToolbar }
                }
            }
            Tab("Inversiones", systemImage: "chart.line.uptrend.xyaxis", value: .investments) {
                NavigationStack {
                    InvestmentsView(vm: investmentsVM, showNewOperation: $showNewInvestment)
                        .toolbar { profileToolbar }
                }
            }
            Tab("Presupuestos", systemImage: "chart.pie", value: .budgets) {
                NavigationStack {
                    BudgetsHubView(vm: budgetsVM, month: dashboardVM.month) { message in openAssistant(message) }
                        .navigationTitle("Presupuestos")
                        .toolbar { profileToolbar }
                }
            }
            // iOS 27 prominent tab: acts as the single "+" action, never as a destination.
            Tab("Añadir", systemImage: "plus", value: .add, role: .prominent) { Color.clear }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(SavedBanner(center: savedBanner))
        .modifier(ActivityIsland(center: island))
        .onChange(of: selection) { old, new in
            if new == .add {
                selection = old == .add ? lastTab : old
                showAdd = true
            } else {
                lastTab = new
            }
        }
        .sheet(isPresented: $showAdd) {
            AddActionSheet(investmentsFirst: lastTab == .investments) { action in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350)) // let the action sheet dismiss first
                    handle(action)
                }
            }
        }
        .sheet(item: $newTransaction) { req in
            TransactionFormView(vm: makeForm(prefill: req.draft, notes: req.notes)) { SiriDonations.transactionRegistered(); refreshAfterSave() }
        }
        .sheet(item: $capture) { mode in
            VexiaCaptureView(vm: VexiaCaptureViewModel(classify: container.classifyTransaction, catalog: container.catalog,
                                                      transcriber: container.makeTranscriber(), language: container.settings.language,
                                                      usage: container.usage.cached),
                             mode: mode) { draft, notes, heard in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    confirm = ConfirmRequest(draft: draft, notes: notes, heard: heard)
                }
            }
        }
        .sheet(item: $confirm) { req in
            VexiaConfirmView(vm: VexiaConfirmViewModel(draft: req.draft, notes: req.notes, heard: req.heard,
                                                      save: container.saveTransaction, catalog: container.catalog),
                             onSaved: { SiriDonations.transactionRegistered(); refreshAfterSave() },
                             onEditAll: { draft in later { newTransaction = FormRequest(draft: draft, notes: req.notes) } },
                             onRetry: { later { capture = .voice } })
        }
        .sheet(isPresented: $showAssistant) {
            NavigationStack {
                AssistantChatView(vm: chatVM)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar", systemImage: "xmark") { showAssistant = false } } }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(vm: SettingsViewModel(settings: container.settings, biometrics: container.biometrics))
        }
        .onChange(of: intents.pending, initial: true) { handleIntents() }
        // Signed in only here: teaches Siri the section and category names used inside phrases.
        .task { VexiaShortcuts.updateAppShortcutParameters() }
        .onChange(of: session.state) { handleIntents() }
        // Outermost so every sheet above (and the ones tabs present) inherits it.
        .environment(savedBanner)
        .environment(island)
    }

    private func handle(_ action: AddActionSheet.Action) {
        switch action {
        case .manual: newTransaction = FormRequest()
        case .voice: capture = .voice
        case .receipt: capture = .receipt
        case .assistant: openAssistant(nil)
        case .investment: selection = .investments; showNewInvestment = true
        }
    }

    /// Siri/Shortcuts requests. Waits while locked: a sheet would show over the lock screen.
    private func handleIntents() {
        guard session.state == .authenticated, !intents.pending.isEmpty else { return }
        for request in intents.take() {
            switch request {
            case .refresh: refreshAfterSave()
            case .open(.rates): selection = .dashboard; showRates = true
            case .open(.assistant): openAssistant(nil)
            case .open(let section): selection = tab(for: section)
            case .search(let term): selection = .transactions; transactionsVM.search(term)
            case .confirm(let p):
                showAdd = false; newTransaction = nil; capture = nil
                later { confirm = ConfirmRequest(draft: p.draft, notes: p.notes, heard: p.heard) }
            }
        }
    }

    private func tab(for section: IntentRouter.Section) -> AppTab {
        switch section {
        case .dashboard, .rates, .assistant: .dashboard
        case .transactions: .transactions
        case .investments: .investments
        case .budgets: .budgets
        }
    }

    private func openAssistant(_ message: String?) {
        showAssistant = true
        if let message { Task { await chatVM.send(message) } }
    }

    private func later(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); action() }
    }

    private func refreshAfterSave() {
        Task { await transactionsVM.reload(); await dashboardVM.load(force: true) }
    }

    @ToolbarContentBuilder private var profileToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: { InitialsAvatar(initials: session.user?.initials ?? "V", size: 32) }
                .accessibilityLabel("Perfil y ajustes")
        }
    }

    private func makeForm(editing: Transaction? = nil, prefill: TransactionDraft? = nil, notes: [String] = []) -> TransactionFormViewModel {
        let vm = TransactionFormViewModel(save: container.saveTransaction, catalog: container.catalog, editing: editing, prefill: prefill,
                                          usage: container.usage)
        vm.aiNotes = notes
        return vm
    }
}

extension VexiaCaptureView.Mode: Identifiable { var id: Self { self } }
