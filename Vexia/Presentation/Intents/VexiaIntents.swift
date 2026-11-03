import AppIntents
import OSLog
import SwiftUI

/// Steps only, never amounts or what was said (Console: subsystem com.vexia.finance.ios, category siri).
private let log = Logger(subsystem: "com.vexia.finance.ios", category: "siri")

// There is no finance App Schema domain (iOS 27.2), so registering is a custom intent reached
// through App Shortcut phrases; search and open adopt the generic `system` schemas so Siri AI
// understands free phrasing for them.

/// "Registra un gasto en Vexia" → Siri asks what → classifier → confirmation → saved, without opening the app.
struct RegisterTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Registrar gasto o ingreso"
    // periphery:ignore - read by the system (Shortcuts app), not by our code
    static let description = IntentDescription("Registra un gasto, ingreso o transferencia diciendo qué fue, cuánto y de qué cuenta.")
    // Background by default; foreground only when something is missing and the user agrees to open Vexia.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    // Writes financial data: never from a locked iPhone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Movimiento", requestValueDialog: "¿Qué gasto o ingreso quieres registrar?")
    var text: String

    @Dependency private var container: AppContainer
    @Dependency private var router: IntentRouter

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        log.notice("register: started")
        guard container.tokens.hasValidTokens else { log.error("register: no session"); throw VexiaIntentError.signedOut }
        let proposal: ProposeTransactionUseCase.Proposal
        do { proposal = try await container.proposeTransaction(text) } catch {
            log.error("register: classify failed \(error.localizedDescription, privacy: .public)")
            throw VexiaIntentError.failed(error.localizedDescription)
        }
        log.notice("register: type=\(proposal.draft.type.rawValue, privacy: .public) missing=\(proposal.missing.count) isTransaction=\(proposal.isTransaction)")
        guard proposal.isTransaction else { throw VexiaIntentError.notAMovement }

        guard proposal.missing.isEmpty else {
            try await continueInForeground(IntentDialog(SiriTransactionText.missing(proposal.missing)))
            // Only after the user agreed: a declined request must not pop up later.
            router.send(.confirm(proposal))
            return .result(dialog: "Completa el movimiento en Vexia.", view: EmptyView())
        }

        try await requestConfirmation(actionName: .add, dialog: IntentDialog(SiriTransactionText.question(proposal)))
        do { try await container.saveTransaction(proposal.draft) } catch {
            log.error("register: save failed \(error.localizedDescription, privacy: .public)")
            throw VexiaIntentError.failed(error.localizedDescription)
        }
        log.notice("register: saved")
        router.send(.refresh)
        return .result(dialog: IntentDialog(SiriTransactionText.done(proposal)), view: SiriTransactionCard(proposal: proposal))
    }
}

/// "Busca mis gastos de Uber en Vexia" → Movimientos filtered by the term, across all history.
@AppIntent(schema: .system.searchInApp)
struct SearchInVexiaIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency private var router: IntentRouter

    @MainActor func perform() async throws -> some IntentResult {
        let term = criteria.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { throw $criteria.needsValueError("¿Qué quieres buscar en Vexia?") }
        log.notice("search: started")
        router.send(.search(term))
        return .result()
    }
}

/// "Abre inversiones en Vexia".
@AppIntent(schema: .system.open)
struct OpenVexiaSectionIntent: OpenIntent {
    var target: VexiaSectionEntity

    @Dependency private var router: IntentRouter

    @MainActor func perform() async throws -> some IntentResult {
        router.send(.open(target.section))
        return .result()
    }
}

/// App sections as an entity: the `system.open` schema only accepts entities as target.
nonisolated struct VexiaSectionEntity: AppEntity {
    let id: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sección"
    static let defaultQuery = SectionQuery()
    static let all = IntentRouter.Section.allCases.map { VexiaSectionEntity(id: $0.rawValue) }

    var section: IntentRouter.Section { IntentRouter.Section(rawValue: id) ?? .dashboard }

    var displayRepresentation: DisplayRepresentation {
        switch section {
        case .dashboard: DisplayRepresentation(title: "Inicio", synonyms: ["resumen", "dashboard"])
        case .transactions: DisplayRepresentation(title: "Movimientos", synonyms: ["transacciones", "gastos", "ingresos"])
        case .investments: DisplayRepresentation(title: "Inversiones", synonyms: ["acciones", "cripto", "portafolio"])
        case .budgets: DisplayRepresentation(title: "Presupuestos", synonyms: ["presupuesto"])
        case .rates: DisplayRepresentation(title: "Tasas", synonyms: ["tasas de cambio", "tipo de cambio", "dólar"])
        case .assistant: DisplayRepresentation(title: "Asistente", synonyms: ["Vexia AI", "chat"])
        }
    }

    struct SectionQuery: EnumerableEntityQuery {
        func allEntities() async throws -> [VexiaSectionEntity] { VexiaSectionEntity.all }
        func entities(for identifiers: [String]) async throws -> [VexiaSectionEntity] {
            VexiaSectionEntity.all.filter { identifiers.contains($0.id) }
        }
        func suggestedEntities() async throws -> [VexiaSectionEntity] { VexiaSectionEntity.all }
    }
}

enum VexiaIntentError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut, notAMovement, failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: "Inicia sesión en Vexia para usarla con Siri."
        case .notAMovement: "No entendí un gasto o ingreso. Prueba con algo como: 50 bolivianos de almuerzo en efectivo."
        case .failed(let reason): "No pude completarlo: \(reason)"
        }
    }
}

struct VexiaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RegisterTransactionIntent(), phrases: [
            "Registra un gasto en \(.applicationName)",
            "Registrar gasto en \(.applicationName)",
            "Anota un gasto en \(.applicationName)",
            "Registra un ingreso en \(.applicationName)",
            "Anota un ingreso en \(.applicationName)",
            "Nuevo movimiento en \(.applicationName)",
        ], shortTitle: "Registrar movimiento", systemImageName: "plus.circle")
        AppShortcut(intent: ConsultSpendingIntent(), phrases: [
            "Cuánto gasté en \(.applicationName)",
            "Mis gastos en \(.applicationName)",
            "Cuánto gasté \(\.$period) en \(.applicationName)",
            "Gastos de \(\.$period) en \(.applicationName)",
            "Cuánto gasté en \(\.$category) en \(.applicationName)",
            "Gastos de \(\.$category) en \(.applicationName)",
        ], shortTitle: "Consultar gastos", systemImageName: "chart.pie")
        AppShortcut(intent: SearchInVexiaIntent(), phrases: [
            "Busca en \(.applicationName)",
            "Buscar movimientos en \(.applicationName)",
        ], shortTitle: "Buscar movimientos", systemImageName: "magnifyingglass")
        AppShortcut(intent: OpenVexiaSectionIntent(), phrases: [
            "Abre \(\.$target) en \(.applicationName)",
            "Muestra \(\.$target) en \(.applicationName)",
        ], shortTitle: "Abrir sección", systemImageName: "square.grid.2x2")
    }
}
