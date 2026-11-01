import Foundation

// MARK: - AI ports (Domain layer)
//
// The Domain layer only knows these protocols. Concrete SDKs (Cloudflare Workers AI,
// Apple Foundation Models, Speech framework, …) live in `Data/AI` as adapters.

/// Text/vision large-language-model port.
protocol LLMProvider: Sendable {
    /// Human-readable identifier (for diagnostics / settings).
    var id: String { get }
    func infer(prompt: String, system: String) async throws -> String
    func infer(prompt: String, system: String, imageJPEG: Data) async throws -> String
}

/// Speech-to-text port. Streams partial transcripts; `stop()` returns the final text.
protocol SpeechTranscriber: AnyObject {
    func requestAuthorization() async -> Bool
    func start(locale: Locale, onPartial: @escaping @MainActor (String) -> Void) throws
    func stop() async -> String
}

/// Source of the classifier system prompt (fetched from backend `/api/prompts/:id`).
protocol PromptRepository: Sendable {
    func prompt(id: String, language: String) async throws -> PromptTemplate
}

nonisolated struct PromptTemplate: Equatable, Sendable {
    let id: String
    let version: String
    let language: String
    let fullPrompt: String

    /// Substitutes template placeholders into the system prompt.
    nonisolated func systemPrompt(expenseCategories: String, incomeCategories: String, accounts: String) -> String {
        var s = fullPrompt
            .replacingOccurrences(of: "{{EXPENSE_CATEGORIES}}", with: expenseCategories)
            .replacingOccurrences(of: "{{INCOME_CATEGORIES}}", with: incomeCategories)
            .replacingOccurrences(of: "{{ACCOUNTS}}", with: accounts)
        for pattern in [#"Parse:\s*"\{\{TEXT\}\}""#, #"Extract from:\s*"\{\{TEXT\}\}""#,
                        #"JSON for\s*"\{\{TEXT\}\}"[:\s]*"#, #"Now output the JSON for:\s*"\{\{TEXT\}\}""#] {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "{{TEXT}}", with: "")
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum AIError: LocalizedError, Equatable {
    case notConfigured(String)
    case emptyTranscript
    case invalidResponse(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let m): "IA no configurada: \(m)"
        case .emptyTranscript: "No se detectó ningún texto"
        case .invalidResponse(let m): "Respuesta inválida de la IA: \(m)"
        case .unavailable(let m): "IA no disponible: \(m)"
        }
    }
}
