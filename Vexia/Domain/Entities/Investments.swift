import Foundation

nonisolated enum OperationType: String, CaseIterable, Identifiable, Sendable {
    case buy, sell, hold
    var id: String { rawValue }
    var title: String { switch self { case .buy: String(localized: "Compra"); case .sell: String(localized: "Venta"); case .hold: String(localized: "Mantener") } }
}

nonisolated struct Investment: Identifiable, Hashable, Sendable {
    let id: Int
    var symbol: String
    var quantity: Double
    var buyPrice: Double
    var currentPrice: Double?
    var fee: Double
    var type: String
    var sector: String?
    var notes: String?
    var operationType: OperationType
    var date: Date
}

nonisolated struct StockPosition: Identifiable, Hashable, Sendable {
    var id: String { symbol }
    var symbol: String
    var netQuantity: Double
    var avgBuyPrice: Double
    var totalInvested: Double
    var currentPrice: Double?
    var currentValue: Double?
    var sector: String?
    var operationCount: Int
}

nonisolated struct AssetPnL: Identifiable, Hashable, Sendable {
    var id: String { symbol + (exchange ?? "") }
    var symbol: String
    var exchange: String?
    var totalInvested: Double
    var currentValue: Double
    var pnl: Double
    var pnlPercent: Double
    var realized: Double
    var unrealized: Double
}

nonisolated struct PnLSummary: Hashable, Sendable {
    var totalPnL: Double
    var totalPnLPercent: Double
    var totalInvested: Double
    var currentValue: Double
    var bestSymbol: String?
    var bestPercent: Double
    var worstSymbol: String?
    var worstPercent: Double
}

nonisolated struct SaleRecord: Identifiable, Hashable, Sendable {
    let id: String
    var symbol: String
    var quantity: Double
    var salePrice: Double
    var saleDate: Date?
    var costBasis: Double
    var realizedPnL: Double
    var realizedPnLPercent: Double
    var exchange: String?
}

nonisolated struct CryptoTransaction: Identifiable, Hashable, Sendable {
    let id: Int
    var cryptoSymbol: String
    var transactionType: OperationType
    var quantity: Double
    var pricePerUnit: Double
    var totalAmount: Double
    var fee: Double
    var exchangePlatform: String?
    var notes: String?
    var isStablecoin: Bool
    var date: Date
}

nonisolated struct CryptoPosition: Identifiable, Hashable, Sendable {
    var id: String { cryptoSymbol }
    var cryptoSymbol: String
    var isStablecoin: Bool
    var netQuantity: Double
    var avgBuyPrice: Double
    var totalInvested: Double
    var operationCount: Int
}

nonisolated struct CryptoPortfolio: Hashable, Sendable {
    var totalInvested: Double
    var currentValue: Double
    var gainLoss: Double
    var gainLossPercent: Double
    var realizedPnL: Double
    var unrealizedPnL: Double
    var uniqueSymbols: Int
    var totalTransactions: Int
}

/// Draft for stock/crypto operations.
nonisolated struct InvestmentDraft: Hashable, Sendable {
    var symbol = ""
    var operationType: OperationType = .buy
    var quantity: Double = 0
    var price: Double = 0
    var currentPrice: Double?
    var fee: Double = 0
    var type = "stock"
    var sector = ""
    var notes = ""
    var exchangePlatform = ""
    var isStablecoin = false
    var date: Date = .now
    var accountId: String?

    var total: Double { (quantity * price * 100).rounded() / 100 }
}
