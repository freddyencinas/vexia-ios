import SwiftUI

/// "Tasas del día": how much 1 USD is worth in each of the user's currencies, with source,
/// deviation vs. external provider, buy/sell when available, and actions.
@Observable
final class RatesViewModel {
    struct Row: Identifiable, Equatable {
        var id: String { code }
        let code: String
        var quote: RateQuote?
        var external: Double?
        var buy: Double?
        var sell: Double?
        var deviation: Double? {
            guard let q = quote, q.source != .external, let e = external, e > 0 else { return nil }
            return (q.rate - e) / e * 100
        }
    }

    private(set) var rows: [Row] = []
    private(set) var updatedAt: Date?
    private(set) var isLoading = false
    var editing: String?
    var message: String?
    let catalog: CatalogRepository
    private let loadRates: LoadTransactionRatesUseCase

    init(catalog: CatalogRepository) { self.catalog = catalog; loadRates = LoadTransactionRatesUseCase(catalog: catalog) }

    func load(forceExternal: Bool = false) async {
        isLoading = true; defer { isLoading = false }
        let codes = await loadRates.currencies()
        async let q = loadRates(codes, forceExternal: forceExternal)
        async let ext = loadRates(codes, forceExternal: true)
        async let country = try? catalog.countryRates()
        let quotes = await q, externals = await ext
        let cr = Dictionary((await country ?? []).map { ($0.currencyCode.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
        rows = codes.map { c in
            let r = cr[c]
            return Row(code: c, quote: quotes[c], external: externals[c]?.rate,
                       buy: (r?.buyRate ?? 0) > 0 ? r?.buyRate : nil, sell: (r?.sellRate ?? 0) > 0 ? r?.sellRate : nil)
        }
        updatedAt = .now
    }

    /// Forces fresh external rates and summarizes them for the island.
    func refresh() async -> IslandMessage {
        let before = Dictionary(rows.compactMap { r in r.quote.map { (r.code, $0.rate) } }, uniquingKeysWith: { a, _ in a })
        await load(forceExternal: true)
        let after = rows.compactMap { r in r.quote.map { (r.code, $0.rate) } }
        guard !after.isEmpty else { return IslandMessage(title: String(localized: "No se pudieron actualizar las tasas"), tone: .failure) }
        let changed = after.contains { code, rate in before[code].map { abs($0 - rate) > 1e-9 } ?? true }
        return IslandMessage(title: changed ? String(localized: "Tasas actualizadas") : String(localized: "Tasas al día"),
                             detail: after.prefix(3).map { "\($0.0) \(Fmt.grouped($0.1))" }.joined(separator: " · "))
    }

    /// Throws so the caller (island) reports the failure; success is shown there too.
    func save(_ code: String, _ v: Double) async throws {
        try await catalog.saveUSDRate(code: code, rate: v, date: .now)
        await load()
    }

    static func name(_ code: String) -> String {
        ["BOB": String(localized: "Boliviano"), "VES": String(localized: "Bolívar"), "EUR": String(localized: "Euro"),
         "ARS": String(localized: "Peso argentino"), "CLP": String(localized: "Peso chileno"),
         "COP": String(localized: "Peso colombiano"), "MXN": String(localized: "Peso mexicano"), "PEN": String(localized: "Sol peruano"),
         "BRL": String(localized: "Real brasileño"), "GBP": String(localized: "Libra esterlina")][code]
            ?? Locale.current.localizedString(forCurrencyCode: code)?.capitalized ?? code
    }

    static func sourceText(_ q: RateQuote?) -> String {
        switch q?.source {
        case .database, .saved: String(localized: "Guardada por ti")
        case .external: String(localized: "Fuente externa")
        case .manual: String(localized: "Manual")
        case .snapshot: String(localized: "Registrada en el movimiento")
        case nil: String(localized: "Sin tasa")
        }
    }
}
