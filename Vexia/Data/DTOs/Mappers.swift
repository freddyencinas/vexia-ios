import Foundation

// JSON → Domain mappers. Key fallbacks (camelCase/snake_case, legacy names) are intentional:
// the backend is not consistent across endpoints.

nonisolated enum Mappers {
    // MARK: Auth
    static func user(_ j: JSON) -> User {
        User(id: j["id"].stringValue, email: j["email"].stringValue,
             firstName: j["firstName"].stringValue, lastName: j["lastName"].stringValue,
             isActive: j["isActive"].bool(default: true), isEmailVerified: j["isEmailVerified"].bool(default: false),
             subscriptionStatus: j["subscriptionStatus"].string ?? "free")
    }

    static func session(_ data: JSON) throws -> AuthSession {
        let t = data["tokens"]
        guard let a = t["accessToken"].string, let r = t["refreshToken"].string else {
            throw APIError(message: String(localized: "Respuesta de autenticación inválida"), code: .decoding, statusCode: nil)
        }
        return AuthSession(user: user(data["user"]), tokens: AuthTokens(accessToken: a, refreshToken: r))
    }

    // MARK: Pagination
    static func pagination(_ j: JSON) -> Pagination {
        let page = j["page"].int ?? 1, totalPages = j["totalPages"].int ?? 1
        return Pagination(page: page, limit: j["limit"].int ?? 20, total: j["total"].intValue,
                          totalPages: totalPages, hasNext: j["hasNext"].bool ?? (page < totalPages))
    }

    // MARK: Transactions
    static func transaction(_ j: JSON) -> Transaction {
        Transaction(
            id: j["id"].intValue, amount: j["amount"].doubleValue,
            currency: j["currency"].stringValue, currencyCode: j["currencyCode"].string,
            description: j["description"].stringValue, date: j["date"].date ?? .now,
            categoryId: j["categoryId"].string, categoryName: CategoryNames.localized(j["categoryName"].string, code: j["categoryCode"].string), categoryIcon: j["categoryIcon"].string,
            tags: j["tags"].array.compactMap(\.string),
            type: TransactionType(rawValue: j["type"].stringValue) ?? .expense,
            isRecurring: j["isRecurring"].bool(default: false), isSystemGenerated: j["isSystemGenerated"].bool(default: false),
            usdAmount: j["usdAmount"].double,
            accountId: j["accountId"].string, accountName: j["accountName"].string,
            fromAccountId: j["fromAccountId"].string, toAccountId: j["toAccountId"].string,
            fromAccountName: j["fromAccountName"].string, toAccountName: j["toAccountName"].string,
            fromAmount: j["fromAmount"].double, toAmount: j["toAmount"].double, exchangeRate: j["exchangeRate"].double,
            currencySnapshots: j["currencySnapshots"].array.map {
                CurrencySnapshot(currencyId: $0["currencyId"].stringValue, currencyCode: $0["currencyCode"].stringValue,
                                 convertedAmount: $0["convertedAmount"].doubleValue, exchangeRate: $0["exchangeRate"].doubleValue)
            })
    }

    /// Body for POST/PUT /transactions.
    static func transactionBody(_ d: TransactionDraft) -> JSON {
        var o: [String: JSON] = [
            "amount": .number(d.amount), "type": .string(d.type.rawValue), "currency": .string(d.currency),
            "description": .string(d.description), "date": .string(DateCoding.dayString(d.date)),
            "accountId": .from(d.accountId),
        ]
        if d.type == .transfer {
            o["fromAccountId"] = .from(d.accountId)
            o["toAccountId"] = .from(d.toAccountId)
            o["fromCurrency"] = .string(d.currency)
            o["toCurrency"] = .string(d.toCurrency.isEmpty ? d.currency : d.toCurrency)
            o["fromAmount"] = .number(d.amount)
            o["toAmount"] = .number(d.toAmount > 0 ? d.toAmount : d.amount)
            o["exchangeRate"] = .from(d.exchangeRate)
        } else {
            o["categoryId"] = .from(d.categoryId)
        }
        if !d.tags.isEmpty { o["tags"] = .array(d.tags.map(JSON.string)) }
        // FX: manual rates feed multi-currency snapshots; customExchangeRate = account currency rate.
        o["customExchangeRate"] = .from(d.customExchangeRate)
        if !d.manualRates.isEmpty { o["manualExchangeRates"] = .object(d.manualRates.mapValues(JSON.number)) }
        if d.isRecurring {
            o["isRecurring"] = true
            o["recurringFrequency"] = .string(d.recurringFrequency.rawValue)
        }
        return .compact(o)
    }

    /// Body for POST /transfers (same-currency transfer).
    static func transferBody(_ d: TransactionDraft) -> JSON {
        .compact(["fromAccountId": .from(d.accountId), "toAccountId": .from(d.toAccountId), "amount": .number(d.amount),
                  "date": .string(DateCoding.dayString(d.date)), "description": d.description.isEmpty ? .null : .string(d.description)])
    }

    /// `/exchange-rates` returns either {rates:[{rate}]} or [{rate}].
    static func firstRate(_ root: JSON) -> Double? {
        let d = root["data"]
        let list = d["rates"].array.isEmpty ? d.array : d["rates"].array
        return list.first?["rate"].double ?? d["rate"].double
    }

    static func summary(_ j: JSON) -> TransactionSummary {
        TransactionSummary(totalIncome: j["totalIncome"].doubleValue, totalExpenses: j["totalExpenses"].doubleValue,
                           netAmount: j["netAmount"].doubleValue, transactionCount: j["transactionCount"].intValue,
                           currencyCode: j["currencyInfo"]["code"].string ?? j["currency"].string)
    }

    static func dependencies(_ j: JSON) -> TransactionDependencies {
        TransactionDependencies(hasDependencies: j["hasDependencies"].bool(default: false),
                                blockDeletion: j["blockDeletion"].bool(default: false),
                                wouldCauseNegativeBalance: j["wouldCauseNegativeBalance"].bool(default: false),
                                message: j["message"].stringValue,
                                affectedCount: j["affectedTransactions"].array.count)
    }

    static func category(_ j: JSON) -> FinancialCategory {
        FinancialCategory(id: j["id"].stringValue, code: j["code"].stringValue, name: CategoryNames.localized(j["name"].stringValue, code: j["code"].string) ?? j["name"].stringValue,
                          icon: j["icon"].string, type: j["type"].stringValue, isGlobal: j["isGlobal"].bool(default: true))
    }

    static func account(_ j: JSON) -> Account {
        let rawType = j["type"].stringValue.lowercased()
        let type: AccountType = rawType == "creditcard" ? .creditCard : AccountType(rawValue: rawType) ?? .other
        return Account(id: j["id"].stringValue, name: j["name"].stringValue, type: type,
                       currencyId: j["currencyId"].stringValue, currencyCode: j["currencyCode"].string,
                       initialBalance: j["initialBalance"].doubleValue, currentBalance: j["currentBalance"].double,
                       color: j["color"].string, isFavorite: j["isFavorite"].bool(default: false))
    }

    static func currencyPreference(_ j: JSON) -> CurrencyPreference {
        CurrencyPreference(id: j["id"].stringValue, currencyId: j["currencyId"].stringValue,
                           currencyCode: j["currencyCode"].string ?? "USD", currencySymbol: j["currencySymbol"].string,
                           isBaseCurrency: j["isBaseCurrency"].bool(default: false))
    }

    /// Accepts camelCase or snake_case keys.
    static func countryRate(_ j: JSON) -> CountryRate {
        CountryRate(id: j["id"].stringValue, currencyCode: j.first("currencyCode", "currency_code").stringValue,
                    currencyName: j.first("currencyName", "currency_name").stringValue, country: j["country"].stringValue,
                    buyRate: j.first("buyRate", "buy_rate").doubleValue, sellRate: j.first("sellRate", "sell_rate").doubleValue,
                    officialRate: j.first("officialRate", "official_rate").doubleValue, source: j["source"].stringValue,
                    updatedAt: j.first("updatedAt", "updated_at").date)
    }

    // MARK: Dashboard — features/dashboard/models/*
    static func overview(_ j: JSON) -> DashboardOverview {
        let s = j["summary"], t = j["trends"], k = j["kpis"]
        return DashboardOverview(
            totalBalance: s["totalBalance"].doubleValue, cashBalance: s["cashBalance"].doubleValue,
            investmentsBalance: s["investmentsBalance"].doubleValue, cryptoBalance: s["cryptoBalance"].doubleValue,
            currencyCode: s["currencyCode"].string ?? s["currency"].string ?? "USD",
            breakdown: s["currencyBreakdown"].array.map {
                .init(currencyId: $0["currencyId"].stringValue, currencyCode: $0["currencyCode"].stringValue,
                      amount: $0["amount"].doubleValue, convertedAmount: $0["convertedAmount"].doubleValue)
            },
            balanceChange: t["balanceChange"].doubleValue, balanceChangePercent: t["balanceChangePercent"].doubleValue,
            savingsRate: k["savingsRate"].doubleValue, monthlyIncome: k["monthlyIncome"].doubleValue,
            monthlyExpenses: k["monthlyExpenses"].doubleValue, averageDailyExpense: k["averageDailyExpense"].doubleValue)
    }

    static func cashFlow(_ j: JSON) -> CashFlow {
        let s = j["summary"]
        return CashFlow(points: j["dataPoints"].array.map {
            .init(period: $0["period"].stringValue, income: $0["income"].doubleValue,
                  expenses: $0["expenses"].doubleValue, netFlow: $0["netFlow"].doubleValue)
        }, totalIncome: s["totalIncome"].doubleValue, totalExpenses: s["totalExpenses"].doubleValue, netFlow: s["netFlow"].doubleValue)
    }

    static func spending(_ j: JSON) -> SpendingAnalysis {
        SpendingAnalysis(
            totalSpent: j["totalSpent"].doubleValue,
            categories: j["categories"].array.map {
                .init(categoryId: $0.first("categoryId", "category").stringValue, categoryCode: $0["categoryCode"].stringValue,
                      categoryName: CategoryNames.localized($0.first("categoryName", "category").stringValue, code: $0["categoryCode"].string) ?? "", amount: $0["amount"].doubleValue,
                      percentage: $0["percentage"].doubleValue, transactionCount: $0["transactionCount"].intValue)
            },
            topExpenses: j["topExpenses"].array.map {
                .init(id: $0["id"].stringValue, description: $0["description"].stringValue, amount: $0["amount"].doubleValue,
                      categoryName: CategoryNames.localized($0["categoryName"].stringValue, code: $0["categoryCode"].string) ?? "", date: $0["date"].date)
            },
            changePercent: j["comparison"]["changePercent"].doubleValue)
    }

    static func performance(_ j: JSON) -> PortfolioPerformance {
        func bucket(_ b: JSON) -> PortfolioPerformance.Bucket {
            .init(totalValue: b["totalValue"].doubleValue, totalInvested: b["totalInvested"].doubleValue,
                  totalGain: b["totalGain"].doubleValue, totalGainPercent: b["totalGainPercent"].doubleValue,
                  assets: b["assets"].array.map {
                      .init(symbol: $0["symbol"].stringValue, name: $0["name"].string, currentValue: $0["currentValue"].doubleValue,
                            unrealizedGain: $0["unrealizedGain"].doubleValue, unrealizedGainPercent: $0["unrealizedGainPercent"].doubleValue)
                  })
        }
        let c = j["combined"]
        return PortfolioPerformance(investments: bucket(j["investments"]), crypto: bucket(j["crypto"]),
                                    combinedValue: c["totalValue"].doubleValue, combinedGain: c["totalGain"].doubleValue,
                                    combinedGainPercent: c["totalGainPercent"].doubleValue)
    }

    // MARK: Investments
    static func investment(_ j: JSON) -> Investment {
        Investment(id: j["id"].intValue, symbol: j["symbol"].stringValue, quantity: j["quantity"].doubleValue,
                   buyPrice: j["buyPrice"].doubleValue, currentPrice: j["currentPrice"].double, fee: j["fee"].doubleValue,
                   type: j["type"].string ?? "stock", sector: j["sector"].string, notes: j["notes"].string,
                   operationType: OperationType(rawValue: j["operationType"].string ?? "buy") ?? .buy,
                   date: j["date"].date ?? .now)
    }

    static func position(_ j: JSON) -> StockPosition {
        StockPosition(symbol: j["symbol"].stringValue, netQuantity: j["netQuantity"].doubleValue,
                      avgBuyPrice: j["avgBuyPrice"].doubleValue, totalInvested: j["totalInvested"].doubleValue,
                      currentPrice: j["currentPrice"].double, currentValue: j["currentValue"].double,
                      sector: j["sector"].string, operationCount: j.first("operationCount", "operationsCount").intValue)
    }

    static func assetPnL(_ j: JSON) -> AssetPnL {
        AssetPnL(symbol: j.first("symbol", "cryptoSymbol").stringValue, exchange: j["exchangePlatform"].string,
                 totalInvested: j["totalInvested"].doubleValue, currentValue: j["currentValue"].doubleValue,
                 pnl: j.first("pnlAbsolute", "totalPnL").doubleValue, pnlPercent: j.first("pnlPercentage", "percentagePnL").doubleValue,
                 realized: j["realizedPnL"].doubleValue, unrealized: j["unrealizedPnL"].doubleValue)
    }

    static func pnlSummary(_ j: JSON) -> PnLSummary {
        PnLSummary(totalPnL: j["totalPnL"].doubleValue, totalPnLPercent: j.first("totalPnLPercentage", "percentagePnL").doubleValue,
                   totalInvested: j["totalInvested"].doubleValue, currentValue: j["currentValue"].doubleValue,
                   bestSymbol: j["bestPerformer"].first("symbol", "cryptoSymbol").string,
                   bestPercent: j["bestPerformer"].first("pnlPercentage", "percentagePnL").doubleValue,
                   worstSymbol: j["worstPerformer"].first("symbol", "cryptoSymbol").string,
                   worstPercent: j["worstPerformer"].first("pnlPercentage", "percentagePnL").doubleValue)
    }

    static func sale(_ j: JSON) -> SaleRecord {
        SaleRecord(id: j["id"].stringValue, symbol: j.first("symbol", "cryptoSymbol").stringValue,
                   quantity: j["quantity"].doubleValue, salePrice: j["salePrice"].doubleValue,
                   saleDate: j.first("saleDate", "date").date, costBasis: j["costBasis"].doubleValue,
                   realizedPnL: j["realizedPnL"].doubleValue, realizedPnLPercent: j["realizedPnLPercentage"].doubleValue,
                   exchange: j["exchangePlatform"].string)
    }

    /// Body for stock operation create/update.
    static func investmentBody(_ d: InvestmentDraft, isUpdate: Bool) -> JSON {
        var o: [String: JSON] = [
            "quantity": .number(d.quantity), "buyPrice": .number(d.price), "fee": .number(d.fee),
            "type": .string(d.type), "date": .string(DateCoding.dayString(d.date)),
            "sector": d.sector.isEmpty ? .null : .string(d.sector), "notes": d.notes.isEmpty ? .null : .string(d.notes),
        ]
        if d.operationType != .sell { o["currentPrice"] = .from(d.currentPrice ?? d.price) }
        if !isUpdate {
            o["symbol"] = .string(d.symbol.uppercased())
            o["operationType"] = .string(d.operationType.rawValue)
            o["accountId"] = .from(d.accountId)
        }
        if !d.manualRates.isEmpty { o["manualExchangeRates"] = .object(d.manualRates.mapValues(JSON.number)) }
        return .compact(o)
    }

    // MARK: Crypto
    static func cryptoTransaction(_ j: JSON) -> CryptoTransaction {
        CryptoTransaction(id: j["id"].intValue, cryptoSymbol: j["cryptoSymbol"].stringValue,
                          transactionType: OperationType(rawValue: j["transactionType"].stringValue) ?? .buy,
                          quantity: j["quantity"].doubleValue, pricePerUnit: j["pricePerUnit"].doubleValue,
                          totalAmount: j["totalAmount"].doubleValue, fee: j["fee"].doubleValue,
                          exchangePlatform: j["exchangePlatform"].string, notes: j["notes"].string,
                          isStablecoin: j["isStablecoin"].bool(default: false), date: j["transactionDate"].date ?? .now)
    }

    static func cryptoPosition(_ j: JSON) -> CryptoPosition {
        CryptoPosition(cryptoSymbol: j["cryptoSymbol"].stringValue, isStablecoin: j["isStablecoin"].bool(default: false),
                       netQuantity: j["netQuantity"].doubleValue, avgBuyPrice: j["avgBuyPrice"].doubleValue,
                       totalInvested: j["totalInvested"].doubleValue, operationCount: j["operationCount"].intValue)
    }

    static func cryptoPortfolio(_ j: JSON) -> CryptoPortfolio {
        let value = j["totalPortfolioValue"].double ?? j["currentValue"].doubleValue
        return CryptoPortfolio(totalInvested: j["totalInvested"].doubleValue, currentValue: value,
                               gainLoss: j["totalGainLoss"].double ?? (value - j["totalInvested"].doubleValue),
                               gainLossPercent: j["percentageGainLoss"].doubleValue,
                               realizedPnL: j["realizedPnL"].doubleValue, unrealizedPnL: j["unrealizedPnL"].doubleValue,
                               uniqueSymbols: j["uniqueSymbols"].intValue, totalTransactions: j["totalTransactions"].intValue)
    }

    /// Body for crypto operation create/update.
    static func cryptoBody(_ d: InvestmentDraft, isUpdate: Bool) -> JSON {
        var o: [String: JSON] = [
            "quantity": .number(d.quantity), "pricePerUnit": .number(d.price),
            "totalAmount": .number(d.total), "fee": .number((d.fee * 100).rounded() / 100),
            "exchangePlatform": d.exchangePlatform.isEmpty ? .null : .string(d.exchangePlatform),
            "notes": d.notes.isEmpty ? .null : .string(d.notes),
            "isStablecoin": .bool(d.isStablecoin), "transactionDate": .string(DateCoding.dayString(d.date)),
        ]
        if !isUpdate {
            o["cryptoSymbol"] = .string(d.symbol.uppercased())
            o["transactionType"] = .string(d.operationType.rawValue)
            o["accountId"] = .from(d.accountId)
        }
        if !d.manualRates.isEmpty { o["manualExchangeRates"] = .object(d.manualRates.mapValues(JSON.number)) }
        return .compact(o)
    }

    // MARK: Budgets — features/budget_planner/models/*
    static func budgetItem(_ j: JSON) -> BudgetItem {
        BudgetItem(id: j["id"].stringValue, itemType: j["itemType"].stringValue, categoryId: j["categoryId"].string,
                   investmentSymbol: j["investmentSymbol"].string, customName: j["customName"].string,
                   targetAmount: j["targetAmount"].doubleValue, currentAmount: j["currentAmount"].doubleValue,
                   targetDirection: j["targetDirection"].string ?? "max", priority: j["priority"].intValue,
                   isActive: j["isActive"].bool(default: true), notes: j["notes"].string, tier: j["tier"].string)
    }

    static func budget(_ j: JSON) -> Budget {
        Budget(id: j["id"].stringValue, name: j["name"].stringValue, description: j["description"].string,
               budgetType: j["budgetType"].stringValue, period: j["period"].stringValue,
               startDate: j["startDate"].date, endDate: j["endDate"].date, totalTargetAmount: j["totalTargetAmount"].double,
               currencyId: j["currencyId"].stringValue, status: j["status"].stringValue,
               aiGenerated: j["aiGenerated"].bool(default: false), items: j["items"].array.map(budgetItem))
    }

    static func progress(_ j: JSON) -> BudgetProgress {
        let s = j["summary"]
        return BudgetProgress(
            budget: budget(j["budget"]),
            items: j["items"].array.map { i in
                var names = i["categoryNames"].array.compactMap(\.string)
                if names.isEmpty, let n = i["categoryName"].string { names = [n] }
                return BudgetItemProgress(item: budgetItem(i), percentage: i["percentage"].doubleValue,
                                          status: i["status"].string ?? "on_track", categoryNames: names)
            },
            totalTarget: s["totalTarget"].doubleValue, totalActual: s["totalActual"].doubleValue,
            variance: s["variance"].doubleValue, complianceRate: s["complianceRate"].doubleValue,
            currencyCode: s["currencyCode"].string ?? "USD")
    }

    static func snapshot(_ j: JSON) -> BudgetSnapshot {
        BudgetSnapshot(id: j["id"].stringValue, snapshotDate: j["snapshotDate"].date, periodStart: j["periodStart"].date,
                       periodEnd: j["periodEnd"].date, totalTarget: j["totalTarget"].doubleValue,
                       totalActual: j["totalActual"].doubleValue, complianceRate: j["complianceRate"].doubleValue,
                       aiAnalysis: j["aiAnalysis"].string)
    }

    static func agentReply(_ j: JSON) -> AgentReply {
        AgentReply(message: j["message"].stringValue,
                   widgets: j["widgets"].array.map { WidgetSpec(type: $0["type"].stringValue, props: $0["props"], interactionId: $0["interactionId"].string) },
                   sessionId: j["metadata"]["sessionId"].string)
    }

    /// Unwraps lists that may live in `data`, `data.data` or a named key.
    static func list(_ root: JSON, keys: String...) -> [JSON] {
        let d = root["data"]
        if case .array(let a) = d { return a }
        for k in keys + ["data"] { if case .array(let a) = d[k] { return a } }
        return []
    }
}
