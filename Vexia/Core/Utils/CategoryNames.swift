import Foundation

/// Spanish names for global categories (backend returns translation keys).
/// Resolves by code first, then by the backend's English name (transactions only carry the name).
nonisolated enum CategoryNames {
    static let byCode: [String: String] = [
        "FOOD": "Alimentación", "TRANSPORT": "Transporte", "HOUSING": "Vivienda", "UTILITIES": "Servicios básicos",
        "HEALTHCARE": "Salud", "HEALTH": "Salud", "EDUCATION": "Educación", "ENTERTAINMENT": "Entretenimiento",
        "MARKET": "Mercado", "SHOPPING": "Compras", "TAXES": "Impuestos", "INVESTMENT_BUY": "Compra de inversiones",
        "CRYPTO_PURCHASE": "Compra de cripto", "SALARY": "Salario", "FREELANCE": "Trabajo independiente",
        "BUSINESS": "Negocio propio", "INVESTMENT": "Inversiones", "REMITTANCE": "Remesas", "RENTAL": "Alquileres",
        "BONUS": "Bonificaciones", "OTHER": "Otros", "INVESTMENT_SELL": "Venta de inversiones",
        "CRYPTO_SALE": "Venta de cripto", "CURRENCY_EXCHANGE": "Cambio de divisas", "TRANSFER": "Traspaso",
    ]
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
