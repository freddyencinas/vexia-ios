import SwiftUI

/// Hands requests from Siri/Shortcuts to the UI. Intents may run before the app has a UI
/// (cold launch) or while it's locked, so requests wait here until `MainTabView` takes them.
@Observable final class IntentRouter {
    nonisolated enum Section: String, CaseIterable, Sendable { case dashboard, transactions, investments, budgets }

    enum Request: Equatable {
        case open(Section)
        case search(String)
        case confirm(ProposeTransactionUseCase.Proposal)
        /// Saved in the background: lists on screen are stale.
        case refresh
    }

    private(set) var pending: [Request] = []

    func send(_ request: Request) {
        // Newer navigation replaces older one; a refresh is only needed once.
        pending.removeAll { old in
            switch (old, request) {
            case (.refresh, .refresh), (.open, .open), (.search, .search), (.open, .search), (.search, .open): true
            default: false
            }
        }
        pending.append(request)
    }

    func take() -> [Request] {
        defer { pending = [] }
        return pending
    }
}

/// What Siri says about a proposed movement. Full sentences: they're also read aloud (AirPods, CarPlay).
enum SiriTransactionText {
    static func summary(_ p: ProposeTransactionUseCase.Proposal) -> String {
        let amount = amount(p, signed: false)
        let from = p.account?.name ?? ""
        let what = item(p)
        switch p.draft.type {
        case .transfer:
            return String(localized: "una transferencia de \(amount) de \(from) a \(p.destination?.name ?? "")")
        case .income:
            return what.map { String(localized: "un ingreso de \(amount) por \($0) en \(category(p)), cuenta \(from)") }
                ?? String(localized: "un ingreso de \(amount) en \(category(p)), cuenta \(from)")
        case .expense:
            return what.map { String(localized: "un gasto de \(amount) por \($0) en \(category(p)), cuenta \(from)") }
                ?? String(localized: "un gasto de \(amount) en \(category(p)), cuenta \(from)")
        }
    }

    // Card lines (SiriTransactionCard)
    static func title(_ p: ProposeTransactionUseCase.Proposal) -> String {
        item(p) ?? (p.draft.type == .transfer ? String(localized: "Traspaso") : category(p))
    }
    static func detail(_ p: ProposeTransactionUseCase.Proposal) -> String {
        p.draft.type == .transfer ? "\(p.account?.name ?? "") → \(p.destination?.name ?? "")" : "\(category(p)) · \(p.account?.name ?? "")"
    }
    static func amount(_ p: ProposeTransactionUseCase.Proposal, signed: Bool = true) -> String {
        let code = p.account?.code ?? p.draft.currencyCode.nilIfEmpty ?? "USD"
        guard signed, p.draft.type != .transfer else { return Fmt.money(p.draft.amount, currency: code) }
        return Fmt.signedMoney(p.draft.amount, currency: code, isIncome: p.draft.type == .income)
    }

    /// What was bought or received ("salteña"); nil when it only repeats the category.
    private static func item(_ p: ProposeTransactionUseCase.Proposal) -> String? {
        let d = p.draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !d.isEmpty, d.caseInsensitiveCompare(category(p)) != .orderedSame else { return nil }
        return d
    }

    // Resources, not Strings: IntentDialog localizes them for the language Siri speaks.
    static func question(_ p: ProposeTransactionUseCase.Proposal) -> LocalizedStringResource {
        "¿Registro \(summary(p))?"
    }

    static func done(_ p: ProposeTransactionUseCase.Proposal) -> LocalizedStringResource {
        "Listo, registré \(summary(p))."
    }

    static func missing(_ fields: [ProposeTransactionUseCase.Missing]) -> LocalizedStringResource {
        let names = fields.map { f -> String in
            switch f {
            case .amount: String(localized: "el monto")
            case .account: String(localized: "la cuenta")
            case .destination: String(localized: "la cuenta destino")
            case .category: String(localized: "la categoría")
            }
        }
        return "Me faltó \(names.formatted(.list(type: .and))). Ábrelo en Vexia para completarlo."
    }

    private static func category(_ p: ProposeTransactionUseCase.Proposal) -> String {
        p.category.map { CategoryNames.localized($0.name, code: $0.code) ?? $0.name } ?? ""
    }
}
