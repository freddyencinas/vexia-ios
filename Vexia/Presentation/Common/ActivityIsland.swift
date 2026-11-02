import SwiftUI

/// Outcome shown when an in-app background task finishes (prices, rates).
struct IslandMessage: Equatable {
    enum Tone: Equatable { case success, warning, failure }
    var title: String
    var detail: String? = nil
    /// Signed change rolled in on the trailing side (e.g. portfolio value delta in USD).
    var delta: Double? = nil
    var tone: Tone = .success
}

/// App-wide state for the island, injected by `MainTabView`.
/// Live Activities don't show in the Dynamic Island while our app is in the foreground,
/// so short in-app tasks get this look-alike that grows out of the island instead.
@Observable final class ActivityIslandCenter {
    enum Phase: Equatable { case working(String), done(IslandMessage) }
    private(set) var phase: Phase?
    private var token = 0

    var isWorking: Bool { if case .working = phase { true } else { false } }

    func run(_ working: String, _ operation: () async -> IslandMessage) async {
        token += 1
        let mine = token
        phase = .working(working)
        let started = ContinuousClock.now
        let message = await operation()
        // Cached answers come back instantly; keep "working" readable instead of a flicker
        let minimum = Duration.milliseconds(900), elapsed = ContinuousClock.now - started
        if elapsed < minimum { try? await Task.sleep(for: minimum - elapsed) }
        guard mine == token else { return }
        phase = .done(message)
    }

    func clear(_ shown: Phase) { if phase == shown { phase = nil } }

    /// Island text for a rate saved as today's rate for everything.
    static func rateSaved(code: String, rate: Double) -> IslandMessage {
        IslandMessage(title: String(localized: "Tasa \(code) guardada"), detail: "1 USD = \(Fmt.grouped(rate)) \(Fmt.symbol(code) ?? code)")
    }
    static func rateFailed(_ error: Error) -> IslandMessage {
        IslandMessage(title: String(localized: "No se pudo guardar la tasa"), detail: error.localizedDescription, tone: .failure)
    }
}

/// Installs the island in its own window above the app, so it also shows over sheets
/// (forms, rate editor). The window ignores touches: the app below stays fully usable.
struct ActivityIsland: ViewModifier {
    let center: ActivityIslandCenter
    func body(content: Content) -> some View {
        content.background(IslandWindowInstaller(center: center).frame(width: 0, height: 0))
    }
}

private struct IslandWindowInstaller: UIViewRepresentable {
    let center: ActivityIslandCenter
    func makeUIView(context: Context) -> InstallerView { InstallerView(center: center) }
    func updateUIView(_ view: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        private let islandCenter: ActivityIslandCenter
        private var islandWindow: UIWindow?

        init(center: ActivityIslandCenter) { islandCenter = center; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard islandWindow == nil, let scene = window?.windowScene else { return }
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .alert + 1
            w.backgroundColor = .clear
            w.isUserInteractionEnabled = false
            let host = UIHostingController(rootView: IslandOverlay(center: islandCenter))
            host.view.backgroundColor = .clear
            w.rootViewController = host
            w.isHidden = false
            islandWindow = w
        }
    }
}

private struct IslandOverlay: View {
    @Bindable var center: ActivityIslandCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var finished = 0

    /// Dynamic Island devices have a top inset of 59+ pt; notch/no-notch devices less.
    private static let islandMinTopInset: CGFloat = 51

    var body: some View {
        GeometryReader { geo in
            let hasIsland = geo.safeAreaInsets.top >= Self.islandMinTopInset && !reduceMotion
            if let phase = center.phase {
                IslandBubble(phase: phase, expanded: expanded || !hasIsland, maxWidth: min(geo.size.width - 24, 380), cameraGap: hasIsland ? 37 : 0)
                    .frame(maxWidth: .infinity)
                    // Sit exactly on the hardware island so the bubble reads as the island growing
                    .offset(y: hasIsland ? 11 - geo.safeAreaInsets.top : 4)
                    .transition(hasIsland ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: center.phase == nil)
        .onChange(of: center.phase == nil) { _, isNil in
            guard !isNil else { return }
            expanded = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) { expanded = true }
            }
        }
        .onChange(of: center.phase) { _, new in if case .done = new { finished += 1 } }
        .sensoryFeedback(trigger: finished) { _, _ in
            guard case .done(let m) = center.phase else { return nil }
            switch m.tone { case .success: return .success; case .warning: return .warning; case .failure: return .error }
        }
        .task(id: center.phase) {
            guard case .done(let m) = center.phase, let shown = center.phase else { return }
            AccessibilityNotification.Announcement([m.title, m.detail].compactMap { $0 }.joined(separator: ". ")).post()
            try? await Task.sleep(for: .seconds(3))
            guard center.phase == shown else { return }
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) { expanded = false } completion: { center.clear(shown) }
        }
    }
}

private struct IslandBubble: View {
    let phase: ActivityIslandCenter.Phase
    let expanded: Bool
    let maxWidth: CGFloat
    /// Height of the hardware island: like the system's expanded island, content sits below the camera.
    let cameraGap: CGFloat
    @State private var shownDelta: Double = 0

    private var message: IslandMessage? { if case .done(let m) = phase { m } else { nil } }

    var body: some View {
        let height: CGFloat = expanded ? cameraGap + (message?.detail != nil ? 62 : 50) : 37
        HStack(spacing: 12) {
            switch phase {
            case .working(let title):
                ProgressView().controlSize(.small).tint(.white)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
            case .done(let m):
                Image(systemName: icon(m.tone)).font(.title3).foregroundStyle(color(m.tone))
                    .symbolEffect(.bounce, value: expanded)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let d = m.detail { Text(d).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1) }
                }
                Spacer(minLength: 8)
                if let delta = m.delta {
                    Text(signed(shownDelta)).font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(delta >= 0 ? Color.green : Color.red)
                        .contentTransition(.numericText(value: shownDelta))
                        .task {
                            try? await Task.sleep(for: .milliseconds(250))
                            withAnimation(.smooth(duration: 0.8)) { shownDelta = delta }
                        }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, expanded ? cameraGap : 0)
        .opacity(expanded ? 1 : 0)
        .blur(radius: expanded ? 0 : 4)
        .frame(width: expanded ? maxWidth : 126, height: height)
        // Black so the bubble reads as the hardware Dynamic Island, in light and dark mode
        .background(.black, in: .rect(cornerRadius: expanded ? (cameraGap > 0 ? 42 : 28) : 18.5, style: .continuous))
        .shadow(color: .black.opacity(expanded ? 0.25 : 0), radius: 12, y: 6)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func icon(_ t: IslandMessage.Tone) -> String {
        switch t { case .success: "checkmark.circle.fill"; case .warning: "exclamationmark.triangle.fill"; case .failure: "xmark.octagon.fill" }
    }
    private func color(_ t: IslandMessage.Tone) -> Color {
        switch t { case .success: .green; case .warning: .orange; case .failure: .red }
    }
    private func signed(_ v: Double) -> String { (v >= 0 ? "+" : "−") + Fmt.money(abs(v)) }
}

#Preview("Isla") {
    @Previewable @State var center = ActivityIslandCenter()
    VStack(spacing: 16) {
        Button {
            Task { await center.run("Actualizando precios de acciones…") {
                try? await Task.sleep(for: .seconds(1.5))
                return IslandMessage(title: "Precios actualizados", detail: "12 símbolos · Valor $5.641,94", delta: 45.2)
            } }
        } label: { Text(verbatim: "Precios") }
        Button {
            Task { await center.run("Actualizando precios de cripto…") { IslandMessage(title: "No se pudieron actualizar", tone: .failure) } }
        } label: { Text(verbatim: "Falla") }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .modifier(ActivityIsland(center: center))
}
