import Foundation

/// Display names for investment sectors. Global sector categories come with English names/codes, and
/// older investments stored the raw sector string instead of a category id, so both are resolved here.
nonisolated enum SectorNames {
    static var byKey: [String: String] { [
        "FINANCE": String(localized: "Finanzas"), "ENERGY": String(localized: "Energía"), "MINING": String(localized: "Minería y materiales"),
        "INDUSTRIAL": String(localized: "Industrial"), "CONSUMER": String(localized: "Consumo masivo"), "HEALTH": String(localized: "Salud"),
        "TECH": String(localized: "Tecnología"), "REAL_ESTATE": String(localized: "Inmobiliario"), "TRANSPORT": String(localized: "Transporte y logística"),
        "UTILITIES": String(localized: "Servicios públicos"),
        "technology": String(localized: "Tecnología"), "healthcare": String(localized: "Salud"), "financials": String(localized: "Finanzas"),
        "consumer discretionary": String(localized: "Consumo discrecional"), "communication services": String(localized: "Servicios de comunicación"),
        "industrials": String(localized: "Industria"), "consumer staples": String(localized: "Consumo básico"), "energy": String(localized: "Energía"),
        "utilities": String(localized: "Servicios públicos"), "real estate": String(localized: "Bienes raíces"), "materials": String(localized: "Materiales"),
        "unknown": String(localized: "Sin sector"),
    ] }

    /// Code ("TECH") or legacy English name ("Technology") → localized label; anything else verbatim.
    static func label(_ raw: String) -> String {
        let map = byKey
        return map[raw.uppercased()] ?? map[raw.lowercased()] ?? raw
    }
}
