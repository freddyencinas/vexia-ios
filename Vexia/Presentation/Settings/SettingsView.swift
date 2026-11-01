import SwiftUI

@Observable
final class SettingsViewModel {
    private let settings: SettingsRepository
    private let biometrics: BiometricAuthenticator
    var biometricEnabled: Bool { didSet { settings.biometricEnabled = biometricEnabled } }
    var themeMode: String { didSet { settings.themeMode = themeMode } }
    var language: String { didSet { settings.language = language } }
    var llmKey: String
    var apiBase: String
    var mcpBase: String
    var newPIN = ""
    var hasPIN: Bool
    var message: String?

    init(settings: SettingsRepository, biometrics: BiometricAuthenticator) {
        self.settings = settings; self.biometrics = biometrics
        biometricEnabled = settings.biometricEnabled
        themeMode = settings.themeMode
        language = settings.language
        llmKey = settings.llmAPIKey ?? ""
        apiBase = AppConfig.apiBaseRaw
        mcpBase = AppConfig.mcpBaseURL
        hasPIN = settings.hasPIN
    }

    var biometryName: String { biometrics.biometryName }
    var biometricsAvailable: Bool { biometrics.isAvailable }
    var onDeviceAIAvailable: Bool { AppleFoundationModelsProvider.isAvailable }

    func toggleBiometrics(_ on: Bool) async {
        // Confirm identity before enabling.
        if on, !(await biometrics.authenticate(reason: "Confirma para activar el bloqueo")) { biometricEnabled = false; return }
        biometricEnabled = on
    }

    func savePIN() {
        guard PINHasher.isValid(newPIN) else { message = "El PIN debe tener 4 a 6 dígitos"; return }
        settings.setPIN(newPIN); newPIN = ""; hasPIN = true; message = "PIN guardado"
    }
    func removePIN() { settings.setPIN(nil); hasPIN = false }

    func saveAdvanced() {
        settings.llmAPIKey = llmKey.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.apiBaseRaw = apiBase.trimmingCharacters(in: .whitespaces)
        AppConfig.mcpBaseURL = mcpBase.trimmingCharacters(in: .whitespaces)
        message = "Configuración guardada"
    }
}

struct SettingsView: View {
    @State var vm: SettingsViewModel
    @Environment(SessionViewModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            Form {
                if let u = session.user {
                    Section {
                        HStack(spacing: 14) {
                            InitialsAvatar(initials: u.initials, size: 56)
                            VStack(alignment: .leading) {
                                Text(u.fullName).font(.headline)
                                Text(u.email).font(.subheadline).foregroundStyle(.secondary)
                                Text(u.hasActiveSubscription ? "Plan Pro" : "Plan gratuito").font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 2).background(.tint.opacity(0.15), in: .capsule)
                            }
                        }
                    }
                }
                Section("Apariencia") {
                    Picker("Tema", selection: Binding(get: { session.themeMode }, set: { session.themeMode = $0 })) {
                        Text("Sistema").tag("system"); Text("Claro").tag("light"); Text("Oscuro").tag("dark")
                    }
                    Picker("Idioma", selection: $vm.language) {
                        Text("Español").tag("es"); Text("English").tag("en")
                    }
                }
                Section {
                    Toggle(isOn: Binding(get: { vm.biometricEnabled }, set: { v in Task { await vm.toggleBiometrics(v) } })) {
                        Label("Bloquear con \(vm.biometryName)", systemImage: "faceid")
                    }
                    .disabled(!vm.biometricsAvailable)
                    if vm.hasPIN {
                        Button("Eliminar PIN", role: .destructive, action: vm.removePIN)
                    } else {
                        HStack {
                            SecureField("Nuevo PIN (4-6 dígitos)", text: $vm.newPIN).keyboardType(.numberPad)
                            Button("Guardar", action: vm.savePIN).disabled(vm.newPIN.count < 4)
                        }
                    }
                } header: { Text("Seguridad") } footer: { Text("El PIN sirve como respaldo si la biometría falla.") }

                Section {
                    LabeledContent("Apple Intelligence", value: vm.onDeviceAIAvailable ? "Disponible" : "No disponible")
                    SecureField("API key LLM en la nube", text: $vm.llmKey)
                } header: { Text("Inteligencia artificial") } footer: {
                    Text("Vexia usa el LLM en la nube (texto + recibos) y, si falla, Apple Intelligence en el dispositivo para texto.")
                }
                Section("Servidor") {
                    TextField("API base URL", text: $vm.apiBase).textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("Agente (MCP) URL", text: $vm.mcpBase).textInputAutocapitalization(.never).keyboardType(.URL)
                    Button("Guardar configuración", action: vm.saveAdvanced)
                }
                Section {
                    Button("Cerrar sesión", role: .destructive) { confirmLogout = true }
                }
                Section {
                    LabeledContent("Versión", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                }
            }
            .navigationTitle("Ajustes")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo", systemImage: "checkmark") { dismiss() } } }
            .confirmationDialog("¿Cerrar sesión?", isPresented: $confirmLogout) {
                Button("Cerrar sesión", role: .destructive) { Task { dismiss(); await session.logout() } }
            }
            .alert(vm.message ?? "", isPresented: Binding(get: { vm.message != nil }, set: { if !$0 { vm.message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}
