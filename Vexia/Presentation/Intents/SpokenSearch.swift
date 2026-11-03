import Foundation

/// Siri AI routes free questions ("gastos en transporte en octubre") to `SearchInVexiaIntent` with the
/// whole sentence as term. As plain text it matches nothing; parsed, it becomes the type/category/month
/// filters Movimientos already has.
nonisolated enum SpokenSearch {
    struct Query: Equatable {
        var type: TransactionType?
        var categoryId: String?
        var monthStart: Date?
        var text: String
    }

    struct Category {
        let id: String
        let type: String
        let names: [String]
    }

    /// Localized name, backend name and spoken variants of every category.
    static func categories(_ cats: [FinancialCategory]) -> [Category] {
        let named = cats.map { (category: $0, name: CategoryNames.localized($0.name, code: $0.code) ?? $0.name) }
        return named.map { c in
            let others = named.filter { $0.category.id != c.category.id }.map(\.name)
            return Category(id: c.category.id, type: c.category.type,
                            names: [c.name, c.category.name] + CategorySpokenNames.synonyms(name: c.name, raw: c.category.name, others: others))
        }
    }

    static func parse(_ term: String, categories: [Category], now: Date = .now, calendar: Calendar = .current) -> Query {
        var words = Words(term)
        let type = typeWords.first { words.contains($0.key) }?.value
        var query = Query(type: type, text: "")

        // Longest name first, so "servicios basicos" wins over "servicios".
        let candidates = categories
            .filter { type == nil || type == .transfer || $0.type == type?.rawValue }
            .flatMap { c in c.names.map { (id: c.id, name: $0) } }
            .sorted { $0.name.count > $1.name.count }
        query.categoryId = candidates.first { words.take($0.name) }?.id

        // "servicios básicos" alone means this month (as Inicio), not a partial list of all history.
        query.monthStart = month(in: &words, now: now, calendar: calendar)
            ?? (query.categoryId != nil ? calendar.dateInterval(of: .month, for: now)?.start : nil)
        typeWords.keys.forEach { _ = words.take($0) }

        // Nothing understood: keep the term as said (names, amounts, accents for the backend search).
        guard query.type != nil || query.categoryId != nil || query.monthStart != nil else {
            query.text = term.trimmingCharacters(in: .whitespacesAndNewlines)
            return query
        }
        query.text = words.remaining(dropping: stopwords)
        return query
    }

    private static func month(in words: inout Words, now: Date, calendar: Calendar) -> Date? {
        guard let current = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
        if ["el mes pasado", "mes pasado", "el mes anterior", "mes anterior", "last month"].contains(where: { words.take($0) }) {
            return calendar.date(byAdding: .month, value: -1, to: current)
        }
        if ["este mes", "this month"].contains(where: { words.take($0) }) { return current }
        guard let index = monthNames.firstIndex(where: { $0.contains { words.take($0) } }) else { return nil }
        let thisYear = calendar.component(.year, from: now)
        // A month without year is the latest one already started: "octubre" in March = last October.
        let year = words.takeYear() ?? (index + 1 > calendar.component(.month, from: now) ? thisYear - 1 : thisYear)
        return calendar.date(from: DateComponents(year: year, month: index + 1, day: 1))
    }

    private static let typeWords: [String: TransactionType] = [
        "gastos": .expense, "gasto": .expense, "expenses": .expense, "expense": .expense,
        "ingresos": .income, "ingreso": .income, "income": .income,
        "transferencias": .transfer, "transferencia": .transfer, "transfers": .transfer, "transfer": .transfer,
    ]

    private static let monthNames: [[String]] = [
        ["enero", "january"], ["febrero", "february"], ["marzo", "march"], ["abril", "april"],
        ["mayo", "may"], ["junio", "june"], ["julio", "july"], ["agosto", "august"],
        ["septiembre", "setiembre", "september"], ["octubre", "october"], ["noviembre", "november"], ["diciembre", "december"],
    ]

    private static let stopwords: Set<String> = [
        "en", "de", "del", "mi", "mis", "el", "la", "los", "las", "por", "para", "que", "cuanto", "gaste",
        "busca", "buscar", "muestra", "muestrame", "movimientos", "movimiento", "transacciones", "vexia",
        "in", "on", "my", "of", "the", "for", "how", "much", "did", "i", "spend", "spent", "show", "search",
    ]
}

/// Words of the term, compared folded (no case/accents) but returned as said.
nonisolated private struct Words {
    private var said: [String]
    private var folded: [String]

    init(_ text: String) {
        said = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        folded = said.map(CategorySpokenNames.fold)
    }

    func contains(_ word: String) -> Bool { folded.contains(word) }

    /// Removes the first run of words equal to `phrase`; true when found.
    mutating func take(_ phrase: String) -> Bool {
        let target = Words(phrase).folded
        guard !target.isEmpty, target.count <= folded.count,
              let start = (0...(folded.count - target.count)).first(where: { Array(folded[$0..<$0 + target.count]) == target })
        else { return false }
        said.removeSubrange(start..<start + target.count)
        folded.removeSubrange(start..<start + target.count)
        return true
    }

    mutating func takeYear() -> Int? {
        guard let i = folded.firstIndex(where: { $0.count == 4 && Int($0).map { (2000...2100).contains($0) } == true }) else { return nil }
        said.remove(at: i)
        return Int(folded.remove(at: i))
    }

    func remaining(dropping stopwords: Set<String>) -> String {
        zip(said, folded).filter { !stopwords.contains($0.1) }.map(\.0).joined(separator: " ")
    }
}
