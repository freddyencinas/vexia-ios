import Foundation

/// GET {API}/api/prompts/{id}?language= (no auth) with 24 h cache + embedded fallback.
final class RemotePromptRepository: PromptRepository {
    private let session: URLSession
    private let defaults: UserDefaults
    private let ttl: TimeInterval = 24 * 3600

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) { self.session = session; self.defaults = defaults }

    /// Version of the prompts bundled in Resources/Prompts. A server copy older than this loses to it,
    /// so a prompt fix ships with the app without waiting for a backend publish (or the 24 h cache).
    static let embeddedVersion = "1.3.0"

    func prompt(id: String, language: String) async throws -> PromptTemplate {
        let key = "vexia_prompt_\(id)_\(language)"
        let bundled = try? Self.embedded(id: id, language: language)
        if let cached = cached(key), Date.now.timeIntervalSince1970 - defaults.double(forKey: key + "_at") < ttl {
            return Self.newest(cached, bundled)
        }
        if let remote = try? await fetch(id: id, language: language) {
            defaults.set(remote.fullPrompt, forKey: key)
            defaults.set(remote.version, forKey: key + "_v")
            defaults.set(Date.now.timeIntervalSince1970, forKey: key + "_at")
            return Self.newest(remote, bundled)
        }
        if let cached = cached(key) { return Self.newest(cached, bundled) }
        guard let bundled else { throw AIError.notConfigured("prompt embebido") }
        return bundled
    }

    nonisolated static func newest(_ server: PromptTemplate, _ bundled: PromptTemplate?) -> PromptTemplate {
        guard let bundled, isOlder(server.version, than: bundled.version) else { return server }
        return bundled
    }

    /// "1.2.0" < "1.3.0"; an unreadable version ("cache") counts as older.
    nonisolated static func isOlder(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int]? {
            let p = v.split(separator: ".").map { Int($0) }
            return p.isEmpty || p.contains(nil) ? nil : p.compactMap { $0 }
        }
        guard let x = parts(a), let y = parts(b) else { return parts(a) == nil }
        for i in 0..<max(x.count, y.count) where (i < x.count ? x[i] : 0) != (i < y.count ? y[i] : 0) {
            return (i < x.count ? x[i] : 0) < (i < y.count ? y[i] : 0)
        }
        return false
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
        return PromptTemplate(id: id, version: embeddedVersion, language: lang, fullPrompt: text)
    }
}
