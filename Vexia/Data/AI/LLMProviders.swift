import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Cloudflare Workers AI adapter.
/// POST {llmBase}/chat/direct-question — Bearer = API key entered in Settings and stored in the Keychain.
final class CloudflareLLMProvider: LLMProvider {
    let id = "cloudflare-workers-ai"
    private let apiKey: @MainActor () -> String?
    private let session: URLSession

    init(apiKey: @escaping @MainActor () -> String?, session: URLSession = .shared) {
        self.apiKey = apiKey; self.session = session
    }

    func infer(prompt: String, system: String) async throws -> String {
        try await request(["userMessage": .string(prompt), "systemPrompt": .string(system),
                           "model": .string(AppConfig.llmModel), "history": []])
    }

    func infer(prompt: String, system: String, imageJPEG: Data) async throws -> String {
        try await request(["userMessage": .string(prompt), "systemPrompt": .string(system), "model": .string(AppConfig.llmModel),
                           "image": .string(imageJPEG.base64EncodedString()), "history": []])
    }

    private func request(_ body: JSON) async throws -> String {
        guard let key = apiKey(), !key.isEmpty else { throw AIError.notConfigured("agrega la API key en Ajustes → Inteligencia artificial") }
        var req = URLRequest(url: URL(string: AppConfig.llmBaseURL + "/chat/direct-question")!, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body.foundation)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw AIError.unavailable("demasiadas solicitudes, intenta en unos segundos") }
        if status >= 500 { throw AIError.unavailable("el servicio de IA no responde (\(status))") }
        guard (200..<300).contains(status) else { throw AIError.invalidResponse("HTTP \(status)") }
        return Self.extract(try JSON.parse(data), raw: data)
    }

    /// Same unwrapping order as `_parseResponse`: answer → (raw VexiaResult) → response → result.
    nonisolated static func extract(_ j: JSON, raw: Data) -> String {
        func text(_ v: JSON) -> String {
            if case .string(let s) = v { return s }
            return (try? JSONSerialization.data(withJSONObject: v.foundation)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        if case .string(let s) = j { return s }
        if !j["answer"].isNull { return text(j["answer"]) }
        if !j["language"].isNull && !j["intent"].isNull { return String(decoding: raw, as: UTF8.self) }
        if !j["response"].isNull { return text(j["response"]) }
        if !j["result"].isNull { return text(j["result"]) }
        return String(decoding: raw, as: UTF8.self)
    }
}

/// Apple Intelligence on-device adapter (Foundation Models framework). Text-only.
/// Demonstrates that the Domain layer is SDK-agnostic: swapping providers needs zero changes in use cases.
final class AppleFoundationModelsProvider: LLMProvider {
    let id = "apple-foundation-models"

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    func infer(prompt: String, system: String) async throws -> String {
        #if canImport(FoundationModels)
        guard Self.isAvailable else { throw AIError.unavailable("Apple Intelligence no está disponible en este dispositivo") }
        let session = LanguageModelSession(instructions: system)
        do { return try await session.respond(to: prompt).content }
        catch {
            #if DEBUG
            print("[AI] apple-foundation-models failed: \(error)")
            #endif
            // Framework errors surface as the generic "operation couldn't be completed" text.
            throw AIError.unavailable("el modelo de Apple en el dispositivo no pudo procesar la solicitud")
        }
        #else
        throw AIError.unavailable("Foundation Models no disponible")
        #endif
    }

    func infer(prompt: String, system: String, imageJPEG: Data) async throws -> String {
        throw AIError.unavailable("el modelo on-device no procesa imágenes")
    }
}

/// Composite: tries providers in order (e.g. cloud → on-device). Pure composition over the port.
final class FallbackLLMProvider: LLMProvider {
    let providers: [LLMProvider]
    var id: String { providers.map(\.id).joined(separator: "→") }
    init(_ providers: [LLMProvider]) { self.providers = providers }

    func infer(prompt: String, system: String) async throws -> String {
        try await first { try await $0.infer(prompt: prompt, system: system) }
    }
    func infer(prompt: String, system: String, imageJPEG: Data) async throws -> String {
        try await first { try await $0.infer(prompt: prompt, system: system, imageJPEG: imageJPEG) }
    }
    private func first(_ op: (LLMProvider) async throws -> String) async throws -> String {
        var errors: [Error] = []
        for p in providers {
            do { return try await op(p) } catch {
                #if DEBUG
                print("[AI] \(p.id) failed: \(error)")
                #endif
                errors.append(error)
            }
        }
        throw Self.mostActionable(errors)
    }

    /// A missing API key is fixable by the user; a later fallback's failure would hide it.
    nonisolated static func mostActionable(_ errors: [Error]) -> Error {
        errors.first { if case .notConfigured? = $0 as? AIError { true } else { false } }
            ?? errors.last ?? AIError.unavailable("sin proveedores")
    }
}
