import SwiftUI

struct BrandHeader: View {
    var subtitle: LocalizedStringKey
    var body: some View {
        VStack(spacing: 12) {
            Image("Logo").resizable().scaledToFit().frame(width: 84, height: 84)
                .clipShape(.rect(cornerRadius: 22))
                .shadow(color: VexiaColor.brandBlue.opacity(0.3), radius: 16, y: 8)
            Text("Vexia").font(.largeTitle.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            VexiaColor.heroGradient.ignoresSafeArea()
            VStack(spacing: 16) {
                Image("Logo").resizable().scaledToFit().frame(width: 96, height: 96).clipShape(.rect(cornerRadius: 24))
                ProgressView().tint(.white)
            }
        }
    }
}

struct LoginView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var vm: LoginViewModel
    @State private var showRegister = false
    @FocusState private var focus: Field?
    enum Field { case email, password }
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _vm = State(initialValue: LoginViewModel(login: container.login, auth: container.auth, googleLogin: container.googleLogin))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { BrandHeader(subtitle: "Tus finanzas, claras y bajo control").frame(maxWidth: .infinity) }
                    .listRowBackground(Color.clear)
                Section {
                    TextField("Correo electrónico", text: $vm.email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .email).submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Contraseña", text: $vm.password)
                        .textContentType(.password).focused($focus, equals: .password).submitLabel(.go)
                        .onSubmit(submit)
                } footer: {
                    if let e = vm.errorMessage { Label(e, systemImage: "exclamationmark.circle").foregroundStyle(VexiaColor.error) }
                }
                Section {
                    Button(action: submit) {
                        HStack { Spacer(); if vm.isLoading { ProgressView() } else { Text("Iniciar sesión").bold() }; Spacer() }
                    }
                    .buttonStyle(.glassProminent).controlSize(.large)
                    .disabled(!vm.canSubmit)
                    .opacity(vm.canSubmit ? 1 : 0.75)
                    .listRowBackground(Color.clear).listRowInsets(.init())
                }
                Section {
                    GoogleSignInButton(isLoading: vm.isGoogleLoading) { googleSignIn() }
                        .disabled(!vm.canUseGoogle)
                        .listRowBackground(Color.clear).listRowInsets(.init())
                } header: {
                    OrDivider()
                }
                Section {
                    Button("¿Olvidaste tu contraseña?") { Task { await vm.forgotPassword() } }.frame(maxWidth: .infinity)
                    Button("¿No tienes cuenta? Regístrate") { showRegister = true }.frame(maxWidth: .infinity)
                }.listRowBackground(Color.clear)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(isPresented: $showRegister) { RegisterView(container: container) }
            .alert("Revisa tu correo", isPresented: Binding(get: { vm.resetMessage != nil }, set: { if !$0 { vm.resetMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(vm.resetMessage ?? "") }
        }
    }

    private func submit() {
        Task { if let u = await vm.submit() { session.didAuthenticate(u) } }
    }

    private func googleSignIn() {
        Task { if let u = await vm.signInWithGoogle() { session.didAuthenticate(u) } }
    }
}

/// "o" separator between password login and social login.
struct OrDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color(.separator)).frame(height: 1)
            Text("o").font(.footnote).foregroundStyle(VexiaColor.textSecondary).textCase(nil)
            Rectangle().fill(Color(.separator)).frame(height: 1)
        }
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}

/// Neutral Google button (Google branding guidelines: white/neutral surface, "G" mark, "Continuar con Google").
struct GoogleSignInButton: View {
    var isLoading: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading { ProgressView() } else { GoogleGMark().frame(width: 18, height: 18) }
                Text("Continuar con Google").font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.primary)
            .background(Color(.systemBackground), in: .capsule)
            .overlay(Capsule().strokeBorder(Color(.separator)))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continuar con Google")
    }
}

/// Four-color Google "G" drawn with arcs (no bundled asset needed).
struct GoogleGMark: View {
    var body: some View {
        Canvas { ctx, size in
            let w = min(size.width, size.height)
            let lw = w * 0.2
            let r = (w - lw) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func arc(_ from: Double, _ to: Double, _ color: Color) {
                var p = Path()
                p.addArc(center: c, radius: r, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                ctx.stroke(p, with: .color(color), style: .init(lineWidth: lw))
            }
            arc(-40, 45, Color(hex: 0x4285F4))      // blue (right)
            arc(45, 135, Color(hex: 0x34A853))      // green (bottom)
            arc(135, 200, Color(hex: 0xFBBC05))     // yellow (left-bottom)
            arc(200, 320, Color(hex: 0xEA4335))     // red (top)
            var bar = Path()
            bar.addRect(CGRect(x: c.x, y: c.y - lw / 2, width: r + lw / 2, height: lw))
            ctx.fill(bar, with: .color(Color(hex: 0x4285F4)))
        }
        .accessibilityHidden(true)
    }
}

struct RegisterView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var vm: RegisterViewModel

    init(container: AppContainer) { _vm = State(initialValue: RegisterViewModel(register: container.register)) }

    var body: some View {
        Form {
            Section("Datos personales") {
                TextField("Nombre", text: $vm.firstName).textContentType(.givenName)
                TextField("Apellido", text: $vm.lastName).textContentType(.familyName)
            }
            Section {
                TextField("Correo electrónico", text: $vm.email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Contraseña (mín. 8)", text: $vm.password).textContentType(.newPassword)
                SecureField("Confirmar contraseña", text: $vm.confirm).textContentType(.newPassword)
            } header: {
                Text("Cuenta")
            } footer: {
                if !vm.passwordsMatch { Text("Las contraseñas no coinciden").foregroundStyle(VexiaColor.error) }
                else if let e = vm.errorMessage { Text(e).foregroundStyle(VexiaColor.error) }
            }
            Section {
                Button {
                    Task { if let u = await vm.submit() { session.didAuthenticate(u) } }
                } label: {
                    HStack { Spacer(); if vm.isLoading { ProgressView() } else { Text("Crear cuenta").bold() }; Spacer() }
                }
                .buttonStyle(.glassProminent).controlSize(.large).disabled(!vm.canSubmit)
                .listRowBackground(Color.clear).listRowInsets(.init())
            }
        }
        .navigationTitle("Crear cuenta")
    }
}

struct LockView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var vm: LockViewModel
    @State private var showPIN = false

    init(container: AppContainer) {
        _vm = State(initialValue: LockViewModel(biometrics: container.biometrics, settings: container.settings))
    }

    var body: some View {
        ZStack {
            VexiaColor.heroGradient.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.white)
                    .symbolEffect(.bounce, value: vm.errorMessage)
                Text("Vexia está bloqueada").font(.title2.bold()).foregroundStyle(.white)
                if showPIN {
                    SecureField("PIN", text: $vm.pin)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center).font(.title.monospacedDigit())
                        .padding().frame(maxWidth: 220)
                        .glassEffect(.regular, in: .capsule)
                        .onChange(of: vm.pin) { _, new in
                            if new.count >= 4, vm.verifyPIN() { Task { await session.unlock() } }
                        }
                    if let e = vm.errorMessage { Text(e).foregroundStyle(.white.opacity(0.9)) }
                }
                Spacer()
                VStack(spacing: 12) {
                    Button { Task { await biometricUnlock() } } label: {
                        Label("Desbloquear con \(vm.biometryName)", systemImage: "faceid").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass).controlSize(.large)
                    if vm.hasPIN && !showPIN {
                        Button("Usar PIN") { withAnimation { showPIN = true } }.foregroundStyle(.white)
                    }
                    Button("Cerrar sesión", role: .destructive) { Task { await session.logout() } }
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 32).padding(.bottom, 24)
            }
        }
        .task { await biometricUnlock() }
    }

    private func biometricUnlock() async {
        if await vm.authenticate() { await session.unlock() }
    }
}
