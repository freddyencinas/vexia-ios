import Foundation

/// Runtime configuration.
/// Values can be overridden from Ajustes → Servidor (persisted in UserDefaults).
enum AppConfig {
    private static let defaults = UserDefaults.standard

    static var apiBaseRaw: String {
        get { defaults.string(forKey: "cfg_api_base_url") ?? defaultAPIBase }
        set { defaults.set(newValue, forKey: "cfg_api_base_url") }
    }
    static var mcpBaseURL: String {
        get { defaults.string(forKey: "cfg_mcp_base_url") ?? defaultMCPBase }
        set { defaults.set(newValue, forKey: "cfg_mcp_base_url") }
    }
    static let llmBaseURL = "https://services.freddy-encinas.workers.dev"
    static let llmModel = "@cf/meta/llama-4-scout-17b-16e-instruct"

    static var apiBaseURL: URL { URL(string: apiBaseRaw.trimmingCharacters(in: .init(charactersIn: "/")) + "/api")! }

    /// Production by default in every build. For local development override in
    /// Ajustes → Servidor (e.g. http://localhost:8787 / http://localhost:8788).
    static let defaultAPIBase = "https://api.vexia.app"
    static let defaultMCPBase = "https://copilot.vexia.app"

    static let timeout: TimeInterval = 30

    /// Google OAuth iOS client (public by design: PKCE, no client secret).
    /// Override with Info.plist key `GIDClientID` if this app gets its own client.
    static var googleIOSClientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "906623323450-83v7l4acm60f3u9tdnfmmifjaltseitl.apps.googleusercontent.com"
    }
}
