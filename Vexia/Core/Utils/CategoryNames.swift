import Foundation

/// Spanish names for global categories (backend returns translation keys).
/// Resolves by code first, then by the backend's English name (transactions only carry the name).
nonisolated enum CategoryNames {
    static var byCode: [String: String] { [
        "FOOD": String(localized: "Alimentación"), "TRANSPORT": String(localized: "Transporte"), "HOUSING": String(localized: "Vivienda"), "UTILITIES": String(localized: "Servicios básicos"),
        "HEALTHCARE": String(localized: "Salud"), "HEALTH": String(localized: "Salud"), "EDUCATION": String(localized: "Educación"), "ENTERTAINMENT": String(localized: "Entretenimiento"),
        "MARKET": String(localized: "Mercado"), "SHOPPING": String(localized: "Compras"), "TAXES": String(localized: "Impuestos"), "INVESTMENT_BUY": String(localized: "Compra de inversiones"),
        "CRYPTO_PURCHASE": String(localized: "Compra de cripto"), "SALARY": String(localized: "Salario"), "FREELANCE": String(localized: "Trabajo independiente"),
        "BUSINESS": String(localized: "Negocio propio"), "INVESTMENT": String(localized: "Inversiones"), "REMITTANCE": String(localized: "Remesas"), "RENTAL": String(localized: "Alquileres"),
        "BONUS": String(localized: "Bonificaciones"), "OTHER": String(localized: "Otros"), "INVESTMENT_SELL": String(localized: "Venta de inversiones"),
        "CRYPTO_SALE": String(localized: "Venta de cripto"), "CURRENCY_EXCHANGE": String(localized: "Cambio de divisas"), "TRANSFER": String(localized: "Traspaso"),
    ] }
    static let byEnglishName: [String: String] = [
        "food & dining": "FOOD", "transportation": "TRANSPORT", "housing": "HOUSING", "utilities": "UTILITIES",
        "healthcare": "HEALTHCARE", "education": "EDUCATION", "entertainment": "ENTERTAINMENT", "market": "MARKET",
        "shopping": "SHOPPING", "taxes": "TAXES", "investment purchase": "INVESTMENT_BUY", "crypto purchase": "CRYPTO_PURCHASE",
        "salary": "SALARY", "freelance": "FREELANCE", "business": "BUSINESS", "investments": "INVESTMENT",
        "remittances": "REMITTANCE", "rental income": "RENTAL", "bonuses": "BONUS", "other": "OTHER",
        "investment sale": "INVESTMENT_SELL", "crypto sale": "CRYPTO_SALE", "currency exchange": "CURRENCY_EXCHANGE",
    ]

    static func localized(_ name: String?, code: String? = nil) -> String? {
        if let code, let es = byCode[code.uppercased()] { return es }
        guard let name else { return nil }
        if let c = byEnglishName[name.lowercased()], let es = byCode[c] { return es }
        return name
    }
}
