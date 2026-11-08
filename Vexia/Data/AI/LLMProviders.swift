import Foundation
import ImageIO
import OSLog
import Vision
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
        guard let key = apiKey(), !key.isEmpty else { throw AIError.notConfigured(String(localized: "agrega la API key en Ajustes → Inteligencia artificial")) }
        var req = URLRequest(url: URL(string: AppConfig.llmBaseURL + "/chat/direct-question")!, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body.foundation)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw AIError.unavailable(String(localized: "demasiadas solicitudes, intenta en unos segundos")) }
        if status >= 500 { throw AIError.unavailable(String(localized: "el servicio de IA no responde (\(status))")) }
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

/// Apple Intelligence on-device adapter (Foundation Models framework): text, and receipts when the model can see.
/// Demonstrates that the Domain layer is SDK-agnostic: swapping providers needs zero changes in use cases.
final class AppleFoundationModelsProvider: LLMProvider {
    let id = "apple-foundation-models"

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    /// Model available and able to read images (iOS 27 vision capability).
    static var readsReceipts: Bool {
        #if canImport(FoundationModels)
        return isAvailable && SystemLanguageModel.default.capabilities.contains(.vision)
        #else
        return false
        #endif
    }

    func infer(prompt: String, system: String) async throws -> String {
        #if canImport(FoundationModels)
        guard Self.isAvailable else { throw AIError.unavailable(String(localized: "Apple Intelligence no está disponible en este dispositivo")) }
        return try await respond(system: system) { try await $0.respond(to: prompt).content }
        #else
        throw AIError.unavailable(String(localized: "Foundation Models no disponible"))
        #endif
    }

    /// The prompt already carries the receipt's OCR text (ClassifyTransactionUseCase).
    func infer(prompt: String, system: String, imageJPEG: Data) async throws -> String {
        #if canImport(FoundationModels)
        guard Self.readsReceipts else { throw AIError.unavailable(String(localized: "el modelo on-device no procesa imágenes")) }
        guard let source = CGImageSourceCreateWithData(imageJPEG as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw AIError.invalidResponse(String(localized: "imagen ilegible")) }
        return try await respond(system: system) { session in
            try await session.respond { prompt; Attachment(image) }.content
        }
        #else
        throw AIError.unavailable(String(localized: "el modelo on-device no procesa imágenes"))
        #endif
    }

    #if canImport(FoundationModels)
    private func respond(system: String, _ op: (LanguageModelSession) async throws -> String) async throws -> String {
        do { return try await op(LanguageModelSession(instructions: system)) }
        catch {
            #if DEBUG
            print("[AI] apple-foundation-models failed: \(error)")
            #endif
            // Framework errors surface as the generic "operation couldn't be completed" text.
            throw AIError.unavailable(String(localized: "el modelo de Apple en el dispositivo no pudo procesar la solicitud"))
        }
    }
    #endif
}

/// On-device text recognition (Vision): works on every iOS 27 device, with or without Apple Intelligence.
final class VisionReceiptTextReader: ReceiptTextReader {
    func text(in imageJPEG: Data) async throws -> String {
        guard let source = CGImageSourceCreateWithData(imageJPEG as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return "" }
        var request = RecognizeTextRequest()
        request.recognitionLanguages = [Locale.Language(identifier: "es-ES"), Locale.Language(identifier: "en-US")]
        return try await request.perform(on: image)
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

/// Which provider answered and which failed (Console: subsystem com.vexia.finance.ios, category ai). Never content.
private let aiLog = Logger(subsystem: "com.vexia.finance.ios", category: "ai")

/// Composite: tries providers in order (on-device → cloud). Pure composition over the port.
/// An answer that is no use (unparseable, receipt without amount) counts as a failure, so the next provider tries.
final class FallbackLLMProvider: LLMProvider {
    let providers: [LLMProvider]
    private let textAnswerIsUsable: @Sendable (String) -> Bool
    private let imageAnswerIsUsable: @Sendable (String) -> Bool
    var id: String { providers.map(\.id).joined(separator: "→") }

    init(_ providers: [LLMProvider],
         textAnswerIsUsable: @escaping @Sendable (String) -> Bool = { _ in true },
         imageAnswerIsUsable: @escaping @Sendable (String) -> Bool = { _ in true }) {
        self.providers = providers
        self.textAnswerIsUsable = textAnswerIsUsable
        self.imageAnswerIsUsable = imageAnswerIsUsable
    }

    func infer(prompt: String, system: String) async throws -> String {
        try await first(accept: textAnswerIsUsable, kind: "text") { try await $0.infer(prompt: prompt, system: system) }
    }
    func infer(prompt: String, system: String, imageJPEG: Data) async throws -> String {
        try await first(accept: imageAnswerIsUsable, kind: "receipt") { try await $0.infer(prompt: prompt, system: system, imageJPEG: imageJPEG) }
    }
    private func first(accept: (String) -> Bool, kind: String, _ op: (LLMProvider) async throws -> String) async throws -> String {
        var errors: [Error] = []
        for p in providers {
            do {
                let answer = try await op(p)
                guard accept(answer) else { throw AIError.invalidResponse(String(localized: "respuesta incompleta")) }
                aiLog.notice("\(kind, privacy: .public) answered by \(p.id, privacy: .public)")
                return answer
            } catch {
                aiLog.notice("\(kind, privacy: .public) failed on \(p.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                errors.append(error)
            }
        }
        throw Self.mostActionable(errors)
    }

    /// A missing API key is fixable by the user; a later fallback's failure would hide it.
    nonisolated static func mostActionable(_ errors: [Error]) -> Error {
        errors.first { if case .notConfigured? = $0 as? AIError { true } else { false } }
            ?? errors.last ?? AIError.unavailable(String(localized: "sin proveedores"))
    }
}
