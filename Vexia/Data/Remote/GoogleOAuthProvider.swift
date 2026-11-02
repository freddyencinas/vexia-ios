import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Google Sign-In without the Google SDK: OAuth 2.0 Authorization Code + PKCE for native apps
/// (RFC 8252) using the iOS OAuth client and its reversed-client-ID redirect scheme.
/// Output is the Google ID token sent to POST /auth/google.
final class GoogleOAuthProvider: NSObject, GoogleIdentityProvider {
    enum OAuthError: LocalizedError {
        case invalidCallback, stateMismatch, missingIDToken, google(String)
        var errorDescription: String? {
            switch self {
            case .invalidCallback, .stateMismatch: String(localized: "No pudimos completar el inicio de sesión con Google. Intenta de nuevo.")
            case .missingIDToken: String(localized: "Google no devolvió tu identidad. Intenta de nuevo.")
            case .google(let m): String(localized: "Google rechazó el inicio de sesión (\(m)).")
            }
        }
    }

    private let clientID: String
    private let urlSession: URLSession
    // Strong ref keeps the auth session alive while Google's sheet is open.
    private var session: ASWebAuthenticationSession?

    init(clientID: String, urlSession: URLSession = .shared) {
        self.clientID = clientID
        self.urlSession = urlSession
    }

    /// "com.googleusercontent.apps.<id>" — reversed client ID, the redirect scheme Google allows for iOS clients.
    var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }
    var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    func signIn() async throws -> String? {
        let verifier = Self.randomURLSafe(bytes: 32)
        let state = Self.randomURLSafe(bytes: 16)
        let nonce = Self.randomURLSafe(bytes: 16)

        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: Self.challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "nonce", value: nonce),
            .init(name: "prompt", value: "select_account"),
        ]

        guard let callback = try await present(auth.url!) else { return nil }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ k: String) -> String? { items.first { $0.name == k }?.value }

        if let err = value("error") { if err == "access_denied" { return nil }; throw OAuthError.google(err) }
        guard value("state") == state else { throw OAuthError.stateMismatch }
        guard let code = value("code") else { throw OAuthError.invalidCallback }
        return try await exchange(code: code, verifier: verifier)
    }

    // MARK: steps

    /// Returns the callback URL, or nil if the user closed the sheet.
    private func present(_ url: URL) async throws -> URL? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL?, Error>) in
            let s = ASWebAuthenticationSession(url: url, callback: .customScheme(redirectScheme)) { url, error in
                if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { cont.resume(returning: nil) }
                else if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: url) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false   // reuse Safari's Google session (one tap)
            session = s
            if !s.start() { cont.resume(throwing: OAuthError.invalidCallback) }
        }
    }

    private func exchange(code: String, verifier: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "code", value: code),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code_verifier", value: verifier),
        ]
        req.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)

        let (data, _) = try await urlSession.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let err = json["error"] as? String { throw OAuthError.google(err) }
        guard let idToken = json["id_token"] as? String else { throw OAuthError.missingIDToken }
        return idToken
    }

    // MARK: PKCE helpers

    nonisolated static func randomURLSafe(bytes: Int) -> String {
        var buf = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &buf)
        return base64URL(Data(buf))
    }

    nonisolated static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated static func base64URL(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension GoogleOAuthProvider: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor(windowScene: scenes.first!)
    }
}
