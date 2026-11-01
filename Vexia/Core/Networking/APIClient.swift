import Foundation

/// HTTP abstraction used by every remote data source.
protocol HTTPClient: AnyObject, Sendable {
    func send(_ method: HTTPMethod, _ path: String, query: [String: String?], body: JSON?, absoluteURL: URL?, timeout: TimeInterval?) async throws -> JSON
}

enum HTTPMethod: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE", patch = "PATCH" }

extension HTTPClient {
    func get(_ path: String, query: [String: String?] = [:]) async throws -> JSON {
        try await send(.get, path, query: query, body: nil, absoluteURL: nil, timeout: nil)
    }
    func post(_ path: String, body: JSON? = nil, query: [String: String?] = [:]) async throws -> JSON {
        try await send(.post, path, query: query, body: body, absoluteURL: nil, timeout: nil)
    }
    func put(_ path: String, body: JSON? = nil) async throws -> JSON {
        try await send(.put, path, query: [:], body: body, absoluteURL: nil, timeout: nil)
    }
    func delete(_ path: String) async throws -> JSON {
        try await send(.delete, path, query: [:], body: nil, absoluteURL: nil, timeout: nil)
    }
}

/// Token storage keys (`access_token`, `refresh_token`, `user_id`).
struct TokenStore {
    let store: SecureStore
    var accessToken: String? { store.string(for: "access_token") }
    var refreshToken: String? { store.string(for: "refresh_token") }
    var hasValidTokens: Bool { accessToken != nil && refreshToken != nil }
    func save(access: String, refresh: String, userId: String? = nil) {
        store.set(access, for: "access_token")
        store.set(refresh, for: "refresh_token")
        if let userId { store.set(userId, for: "user_id") }
    }
    func clearAll() { ["access_token", "refresh_token", "user_id"].forEach { store.set(nil, for: $0) } }
}

/// URLSession client = Dio + AuthInterceptor + ErrorInterceptor + LocaleInterceptor.
final class APIClient: HTTPClient {
    private let session: URLSession
    private let tokens: TokenStore
    private var refreshTask: Task<Bool, Never>?
    /// Called when refresh fails → session expired (AuthViewModel listens).
    var onSessionExpired: (() -> Void)?
    var languageCode: String = Locale.current.language.languageCode?.identifier ?? "es"

    init(tokens: TokenStore, session: URLSession = .shared) {
        self.tokens = tokens
        self.session = session
    }

    func send(_ method: HTTPMethod, _ path: String, query: [String: String?], body: JSON?, absoluteURL: URL?, timeout: TimeInterval?) async throws -> JSON {
        do {
            return try await perform(method, path, query: query, body: body, absoluteURL: absoluteURL, timeout: timeout)
        } catch let e as APIError where e.code == .unauthorized && !path.contains("/auth/refresh") && !path.contains("/auth/login") {
            // AuthInterceptor: single in-flight refresh, then retry once.
            guard tokens.refreshToken != nil else { tokens.clearAll(); onSessionExpired?(); throw e }
            if await refreshTokens() {
                return try await perform(method, path, query: query, body: body, absoluteURL: absoluteURL, timeout: timeout)
            }
            tokens.clearAll()
            onSessionExpired?()
            throw e
        }
    }

    /// POST /auth/refresh {refreshToken} → data.tokens.{accessToken, refreshToken}
    func refreshTokens() async -> Bool {
        if let refreshTask { return await refreshTask.value }
        let task = Task<Bool, Never> { [weak self] in
            guard let self, let rt = self.tokens.refreshToken else { return false }
            do {
                let res = try await self.perform(.post, "/auth/refresh", query: [:], body: ["refreshToken": .string(rt)], absoluteURL: nil, timeout: nil)
                let t = res["data"]["tokens"]
                guard let a = t["accessToken"].string, let r = t["refreshToken"].string else { return false }
                self.tokens.save(access: a, refresh: r)
                return true
            } catch { return false }
        }
        refreshTask = task
        let ok = await task.value
        refreshTask = nil
        return ok
    }

    private func perform(_ method: HTTPMethod, _ path: String, query: [String: String?], body: JSON?, absoluteURL: URL?, timeout: TimeInterval?) async throws -> JSON {
        var comps = URLComponents(url: absoluteURL ?? AppConfig.apiBaseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }.sorted { $0.name < $1.name }
        if !items.isEmpty { comps.queryItems = items }
        var req = URLRequest(url: comps.url!, timeoutInterval: timeout ?? AppConfig.timeout)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("\(languageCode)-\(languageCode == "en" ? "EN" : "ES")", forHTTPHeaderField: "Accept-Language")
        if let token = tokens.accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body.foundation) }

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch let e as URLError { throw APIError.from(urlError: e) }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSON.parse(data)) ?? .string(String(decoding: data, as: UTF8.self))
        #if DEBUG
        print("[API] \(method.rawValue) \(comps.url!.absoluteString) → \(status)")
        #endif
        guard (200..<300).contains(status) else { throw APIError.from(status: status, body: json) }
        return json
    }
}
