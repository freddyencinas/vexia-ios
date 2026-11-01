import Foundation

/// GET {API}/api/prompts/{id}?language= (no auth) with 24 h cache + embedded fallback.
final class RemotePromptRepository: PromptRepository {
    private let session: URLSession
    private let defaults: UserDefaults
    private let ttl: TimeInterval = 24 * 3600

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) { self.session = session; self.defaults = defaults }

    func prompt(id: String, language: String) async throws -> PromptTemplate {
        let key = "vexia_prompt_\(id)_\(language)"
        if let cached = cached(key), Date.now.timeIntervalSince1970 - defaults.double(forKey: key + "_at") < ttl { return cached }
        if let remote = try? await fetch(id: id, language: language) {
            defaults.set(remote.fullPrompt, forKey: key)
            defaults.set(remote.version, forKey: key + "_v")
            defaults.set(Date.now.timeIntervalSince1970, forKey: key + "_at")
            return remote
        }
        if let cached = cached(key) { return cached }
        return try Self.embedded(id: id, language: language)
    }

    private func cached(_ key: String) -> PromptTemplate? {
        guard let p = defaults.string(forKey: key) else { return nil }
        return PromptTemplate(id: key, version: defaults.string(forKey: key + "_v") ?? "cache", language: "", fullPrompt: p)
    }

    private func fetch(id: String, language: String) async throws -> PromptTemplate {
        var c = URLComponents(url: AppConfig.apiBaseURL.appending(path: "/prompts/\(id)"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "language", value: language)]
        let (data, _) = try await session.data(for: URLRequest(url: c.url!, timeoutInterval: 8))
        let j = try JSON.parse(data)
        guard j["success"].bool == true, let full = j["data"]["fullPrompt"].string else { throw AIError.invalidResponse("prompt") }
        return PromptTemplate(id: j["data"]["id"].string ?? id, version: j["data"]["version"].string ?? "?", language: language, fullPrompt: full)
    }

    static func embedded(id: String, language: String) throws -> PromptTemplate {
        let lang = language == "en" ? "en" : "es"
        guard let url = Bundle.main.url(forResource: "\(id)_\(lang)", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { throw AIError.notConfigured("prompt embebido") }
        return PromptTemplate(id: id, version: "embedded-1.2.0", language: lang, fullPrompt: text)
    }
}
