import AppIntents
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.vexia.finance.ios", category: "siri")

/// "¿Cuánto gasté en Vexia?" → answered aloud with a card, without opening the app.
/// Period defaults to this month and category is optional, so the plain phrase never asks anything.
struct ConsultSpendingIntent: AppIntent {
    static let title: LocalizedStringResource = "Consultar gastos"
    // periphery:ignore - read by the system (Shortcuts app), not by our code
    static let description = IntentDescription("Dice cuánto gastaste hoy, esta semana o este mes, en total o en una categoría.")
    static let supportedModes: IntentModes = .background
    // Speaks financial data: never from a locked iPhone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Periodo", default: .thisMonth)
    var period: SpendingPeriod

    @Parameter(title: "Categoría")
    var category: ExpenseCategoryEntity?

    @Dependency private var container: AppContainer

    static var parameterSummary: some ParameterSummary {
        Summary("Gastos de \(\.$period) en \(\.$category)")
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        log.notice("consult: started")
        guard container.tokens.hasValidTokens else { throw VexiaIntentError.signedOut }
        let report: ConsultSpendingUseCase.Report
        do {
            report = try await container.consultSpending(period: period, categoryId: category?.id, categoryName: category?.name)
        } catch {
            log.error("consult: failed \(error.localizedDescription, privacy: .public)")
            throw VexiaIntentError.failed(error.localizedDescription)
        }
        return .result(dialog: IntentDialog(stringLiteral: SpendingAnswer.sentence(report)), view: SiriSpendingCard(report: report))
    }
}

extension SpendingPeriod: AppEnum {
    nonisolated static let typeDisplayRepresentation: TypeDisplayRepresentation = "Periodo"
    // Lowercase: they're spoken inside phrases ("cuánto gasté esta semana en Vexia").
    nonisolated static let caseDisplayRepresentations: [SpendingPeriod: DisplayRepresentation] = [
        .today: DisplayRepresentation(title: "hoy"),
        .thisWeek: DisplayRepresentation(title: "esta semana", synonyms: ["la semana"]),
        .thisMonth: DisplayRepresentation(title: "este mes", synonyms: ["el mes"]),
        .lastMonth: DisplayRepresentation(title: "el mes pasado", synonyms: ["mes pasado", "el mes anterior"]),
    ]
}

/// The user's expense categories, so Siri can match "en Almuerzo" or "en servicios básicos".
nonisolated struct ExpenseCategoryEntity: AppEntity {
    let id: String
    let name: String
    /// Spoken/transcribed variants ("servicio basico") so App Shortcut phrases still match.
    var synonyms: [String] = []

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Categoría"
    static let defaultQuery = ExpenseCategoryQuery()
    // Names are already localized data; an interpolated literal would add an empty "%@" key to the catalog.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name),
                              synonyms: synonyms.map { LocalizedStringResource(stringLiteral: $0) })
    }

    struct ExpenseCategoryQuery: EntityStringQuery {
        @Dependency private var container: AppContainer

        @MainActor func entities(for identifiers: [String]) async throws -> [ExpenseCategoryEntity] {
            await all().filter { identifiers.contains($0.id) }
        }
        @MainActor func entities(matching string: String) async throws -> [ExpenseCategoryEntity] {
            let q = CategorySpokenNames.fold(string)
            return await all().filter { ([$0.name] + $0.synonyms).contains { CategorySpokenNames.fold($0).contains(q) } }
        }
        @MainActor func suggestedEntities() async throws -> [ExpenseCategoryEntity] { await all() }

        /// Empty when signed out: Siri then just asks without suggestions.
        @MainActor private func all() async -> [ExpenseCategoryEntity] {
            let cats = (try? await container.catalog.categories(type: "expense")) ?? []
            let named = cats.map { (category: $0, name: CategoryNames.localized($0.name, code: $0.code) ?? $0.name) }
            return named.map { c in
                ExpenseCategoryEntity(id: c.category.id, name: c.name,
                                      synonyms: CategorySpokenNames.synonyms(name: c.name, raw: c.category.name,
                                                                             others: named.filter { $0.category.id != c.category.id }.map(\.name)))
            }
        }
    }
}

/// Ways a category may be said or transcribed: Siri matches phrase parameters against these strings,
/// so "Almuerzo" matched but "servicio basico" missed "Servicios básicos".
nonisolated enum CategorySpokenNames {
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    static func synonyms(name: String, raw: String, others: [String]) -> [String] {
        let words = name.split(separator: " ").map(String.init)
        // Singular ↔ plural on every word long enough to be a noun/adjective ("Servicios básicos" ↔ "Servicio básico").
        let number = words.map { $0.count >= 4 ? ($0.hasSuffix("s") ? String($0.dropLast()) : $0 + "s") : $0 }.joined(separator: " ")
        var candidates = [fold(name), number, fold(number)]
        // First word alone ("servicios"), only if no other category starts with it.
        if words.count > 1, let first = words.first, first.count >= 5,
           !others.contains(where: { fold($0).hasPrefix(fold(first)) }) {
            candidates.append(first)
        }
        if fold(raw) != fold(name) { candidates.append(raw) }   // backend name ("Utilities")
        var seen: Set<String> = [name.lowercased()]
        return candidates.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
