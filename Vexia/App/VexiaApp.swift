import AppIntents
import SwiftUI

@main
struct VexiaApp: App {
    @State private var container: AppContainer
    @State private var session: SessionViewModel
    @State private var intents: IntentRouter
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let c = AppContainer()
        _container = State(initialValue: c)
        _session = State(initialValue: SessionViewModel(container: c))
        // Siri/Shortcuts intents run in this process and share these instances with the UI.
        // Created here, not read back from @State: a State read in init may not be the installed instance.
        let router = IntentRouter()
        _intents = State(initialValue: router)
        AppDependencyManager.shared.add(dependency: c)
        AppDependencyManager.shared.add(dependency: router)
        // Teaches Siri the section names used inside "Abre ${target} en Vexia".
        VexiaShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .environment(session)
                .environment(intents)
                .environment(\.container, container)
                .tint(VexiaColor.brandBlue)
                .task { await session.start() }
                .onChange(of: scenePhase) { _, p in session.scenePhaseChanged(p) }
        }
    }
}

/// Route switch (splash → lock / dashboard / login).
struct RootView: View {
    let container: AppContainer
    @Environment(SessionViewModel.self) private var session

    var body: some View {
        @Bindable var session = session
        ZStack {
            // Same view identity in .authenticated and .locked → tab/navigation state survives the lock.
            if session.user != nil && (session.state == .authenticated || session.state == .locked) {
                MainTabView(container: container, session: session)
            }
            switch session.state {
            case .launching: SplashView()
            case .unauthenticated: LoginView(container: container).transition(.opacity)
            case .locked: LockView(container: container).transition(.opacity)
            case .authenticated: EmptyView()
            }
        }
        .animation(.smooth, value: session.state)
        .preferredColorScheme(colorScheme)
        .alert("Sesión expirada", isPresented: $session.sessionExpiredAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text("Vuelve a iniciar sesión para continuar.") }
    }

    private var colorScheme: ColorScheme? {
        switch session.themeMode { case "light": .light; case "dark": .dark; default: nil }
    }
}
