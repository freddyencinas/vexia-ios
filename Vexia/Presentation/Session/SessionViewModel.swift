import SwiftUI

/// Global auth/lock state machine + app lifecycle lock logic.
@Observable
final class SessionViewModel {
    enum State: Equatable { case launching, unauthenticated, locked, authenticated }

    private(set) var state: State = .launching
    private(set) var user: User?
    var sessionExpiredAlert = false
    /// Observable copy of the persisted theme so RootView re-renders immediately.
    var themeMode: String { didSet { container.settings.themeMode = themeMode } }
    private var didBackground = false

    private let container: AppContainer
    init(container: AppContainer) {
        self.container = container
        themeMode = container.settings.themeMode
        container.api.onSessionExpired = { [weak self] in
            guard let self, self.state == .authenticated else { return }
            self.user = nil
            self.state = .unauthenticated
            self.sessionExpiredAlert = true
        }
    }

    func start() async {
        switch await container.restoreSession() {
        case .authenticated(let u): user = u; state = .authenticated
        case .locked: state = .locked
        case .unauthenticated: state = .unauthenticated
        }
    }

    func didAuthenticate(_ user: User) { self.user = user; state = .authenticated }

    /// Unlock after biometrics/PIN → best-effort refresh then /auth/me.
    func unlock() async {
        _ = await container.auth.refreshSession()
        do { user = try await container.auth.currentUser(); state = .authenticated }
        catch { await container.auth.logout(); state = .unauthenticated; sessionExpiredAlert = true }
    }

    func logout() async {
        await container.auth.logout()
        user = nil
        state = .unauthenticated
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background: didBackground = true
        case .active:
            if didBackground, state == .authenticated, container.settings.biometricEnabled { state = .locked }
            didBackground = false
        default: break
        }
    }

    // periphery:ignore - pending: reload profile after editing it
    func refreshUser() async {
        if let u = try? await container.auth.currentUser() { user = u }
    }
}
