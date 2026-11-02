import SwiftUI

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
                                Text(u.hasActiveSubscription ? String(localized: "Plan Pro") : String(localized: "Plan gratuito")).font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 2).background(.tint.opacity(0.15), in: .capsule)
                            }
                        }
                    }
                }
                Section("Apariencia") {
                    Picker("Tema", selection: Binding(get: { session.themeMode }, set: { session.themeMode = $0 })) {
                        Text("Sistema").tag("system"); Text("Claro").tag("light"); Text("Oscuro").tag("dark")
                    }
                    // iOS restarts the app on a per-app language change, so every layer picks it up.
                    Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                        LabeledContent("Idioma", value: Locale.current.localizedString(forLanguageCode: vm.language)?.capitalized ?? vm.language)
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
                    LabeledContent("Apple Intelligence", value: vm.onDeviceAIAvailable ? String(localized: "Disponible") : String(localized: "No disponible"))
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
