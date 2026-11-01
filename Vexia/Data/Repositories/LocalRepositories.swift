import Foundation
import LocalAuthentication

/// UserDefaults (`biometric_enabled`, `theme_mode`) + Keychain (`app_pin_hash`, `app_pin_salt`).
final class LocalSettingsRepository: SettingsRepository {
    private let defaults: UserDefaults
    private let secure: SecureStore

    init(defaults: UserDefaults = .standard, secure: SecureStore) { self.defaults = defaults; self.secure = secure }

    var biometricEnabled: Bool {
        get { defaults.bool(forKey: "biometric_enabled") }
        set { defaults.set(newValue, forKey: "biometric_enabled") }
    }
    var themeMode: String {
        get { defaults.string(forKey: "theme_mode") ?? "system" }
        set { defaults.set(newValue, forKey: "theme_mode") }
    }
    var language: String {
        get { defaults.string(forKey: "app_language") ?? (Locale.current.language.languageCode?.identifier == "en" ? "en" : "es") }
        set { defaults.set(newValue, forKey: "app_language") }
    }
    var hasPIN: Bool { secure.string(for: "app_pin_hash") != nil }

    func setPIN(_ pin: String?) {
        guard let pin else { secure.set(nil, for: "app_pin_hash"); secure.set(nil, for: "app_pin_salt"); return }
        let salt = PINHasher.makeSalt()
        secure.set(salt, for: "app_pin_salt")
        secure.set(PINHasher.hash(pin: pin, salt: salt), for: "app_pin_hash")
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let salt = secure.string(for: "app_pin_salt"), let hash = secure.string(for: "app_pin_hash") else { return false }
        return PINHasher.hash(pin: pin, salt: salt) == hash
    }

    var llmAPIKey: String? {
        get { secure.string(for: "llm_api_key") }
        set { secure.set(newValue?.isEmpty == true ? nil : newValue, for: "llm_api_key") }
    }
}

/// LocalAuthentication adapter (passcode fallback allowed).
final class DeviceBiometricAuthenticator: BiometricAuthenticator {
    var isAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }
    var biometryName: String {
        let c = LAContext(); _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch c.biometryType { case .faceID: return "Face ID"; case .touchID: return "Touch ID"; case .opticID: return "Optic ID"; default: return "código" }
    }
    func authenticate(reason: String) async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
