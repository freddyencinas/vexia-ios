import Foundation

/// Structured output of the expense/income classifier.
/// Structured transaction proposal returned by the AI classifier.
nonisolated struct VexiaResult: Equatable, Sendable {
    enum Intent: String, Sendable { case expense, income, transfer, query, unknown }

    var language: String
    var intent: Intent
    var confidence: Double
    var needsConfirmation: Bool
    var form: FormPrefill
    var missingFields: [String]
    var warnings: [String]
    var clarifyingQuestions: [ClarifyingQuestion]

    struct FormPrefill: Equatable, Sendable {
        var type: String?
        var amount: Double?
        var currency: String?
        var description: String?
        var dateISO: String?
        var dateRelative: String?
        var categoryId: String?
        var accountFromId: String?
        var accountToId: String?
        var merchantOrPayee: String?
        var tags: [String] = []

        /// Resolves `date.iso` / `date.relative` into a concrete date.
        nonisolated func resolvedDate(now: Date = .now, calendar: Calendar = .current) -> Date {
            if let iso = dateISO, let d = DateCoding.parse(iso) { return d }
            switch dateRelative?.lowercased() {
            case "yesterday": return calendar.date(byAdding: .day, value: -1, to: now) ?? now
            case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: now) ?? now
            default: return now
            }
        }
    }

    struct ClarifyingQuestion: Equatable, Sendable {
        var field: String
        var question: String
    }
}

/// Strict JSON parser (same tolerance rules as `VexiaResult.parseStrictJson` + `_sanitizeRawJson`).
nonisolated enum VexiaResultParser {
    nonisolated static func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: #"^```(json)?"#, with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: #"```$"#, with: "", options: .regularExpression)
        }
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") {
            s = String(s[start...end])
        }
        return s
    }

    nonisolated static func parse(_ raw: String) throws -> VexiaResult {
        let text = sanitize(raw)
        guard let data = text.data(using: .utf8),
              let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AIError.invalidResponse(String(localized: "JSON no es un objeto"))
        }
        let form = map["form_prefill"] as? [String: Any] ?? [:]
        let amount = form["amount"] as? [String: Any] ?? [:]
        let date = form["date"] as? [String: Any] ?? [:]
        let validation = map["validation"] as? [String: Any] ?? [:]

        func str(_ any: Any?) -> String? {
            guard let s = (any as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
            return s
        }
        func num(_ any: Any?) -> Double? {
            if let d = any as? Double { return d }
            if let i = any as? Int { return Double(i) }
            if let s = any as? String {
                let cleaned = s.replacingOccurrences(of: ",", with: ".")
                    .replacingOccurrences(of: #"[^0-9.\-]"#, with: "", options: .regularExpression)
                return Double(cleaned)
            }
            return nil
        }
        func list(_ any: Any?) -> [String] { (any as? [Any])?.compactMap { $0 as? String } ?? [] }
        func bool(_ any: Any?) -> Bool {
            if let b = any as? Bool { return b }
            if let s = any as? String { return ["true", "yes", "1"].contains(s.lowercased()) }
            return false
        }

        let intentRaw = (str(map["intent"]) ?? "unknown").lowercased()
        return VexiaResult(
            language: str(map["language"]) ?? "es",
            intent: VexiaResult.Intent(rawValue: intentRaw) ?? .unknown,
            confidence: num(map["confidence"]) ?? 0,
            needsConfirmation: bool(map["needs_confirmation"]),
            form: .init(
                type: str(form["type"]),
                amount: num(amount["value"]),
                currency: str(amount["currency"]),
                description: str(form["description"]),
                dateISO: str(date["iso"]),
                dateRelative: str(date["relative"]),
                categoryId: str(form["category_id"]),
                accountFromId: str(form["account_from_id"]),
                accountToId: str(form["account_to_id"]),
                merchantOrPayee: str(form["merchant_or_payee"]),
                tags: list(form["tags"])
            ),
            missingFields: list(validation["missing_fields"]),
            warnings: list(validation["warnings"]),
            clarifyingQuestions: ((map["clarifying_questions"] as? [[String: Any]]) ?? []).map {
                .init(field: str($0["field"]) ?? "", question: str($0["question"]) ?? "")
            }
        )
    }
}
