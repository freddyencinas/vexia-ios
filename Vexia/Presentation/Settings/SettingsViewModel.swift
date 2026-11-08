import SwiftUI

@Observable
final class SettingsViewModel {
    private let settings: SettingsRepository
    private let biometrics: BiometricAuthenticator
    var biometricEnabled: Bool { didSet { settings.biometricEnabled = biometricEnabled } }
    var themeMode: String { didSet { settings.themeMode = themeMode } }
    var language: String { settings.language }
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
        llmKey = settings.llmAPIKey ?? ""
        apiBase = AppConfig.apiBaseRaw
        mcpBase = AppConfig.mcpBaseURL
        hasPIN = settings.hasPIN
    }

    var biometryName: String { biometrics.biometryName }
    var biometricsAvailable: Bool { biometrics.isAvailable }
    var onDeviceAIAvailable: Bool { AppleFoundationModelsProvider.isAvailable }
    var receiptsOnDevice: Bool { AppleFoundationModelsProvider.readsReceipts }

    func toggleBiometrics(_ on: Bool) async {
        // Confirm identity before enabling.
        if on, !(await biometrics.authenticate(reason: String(localized: "Confirma para activar el bloqueo"))) { biometricEnabled = false; return }
        biometricEnabled = on
    }

    func savePIN() {
        guard PINHasher.isValid(newPIN) else { message = String(localized: "El PIN debe tener 4 a 6 dígitos"); return }
        settings.setPIN(newPIN); newPIN = ""; hasPIN = true; message = String(localized: "PIN guardado")
    }
    func removePIN() { settings.setPIN(nil); hasPIN = false }

    func saveAdvanced() {
        settings.llmAPIKey = llmKey.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.apiBaseRaw = apiBase.trimmingCharacters(in: .whitespaces)
        AppConfig.mcpBaseURL = mcpBase.trimmingCharacters(in: .whitespaces)
        message = String(localized: "Configuración guardada")
    }
}
