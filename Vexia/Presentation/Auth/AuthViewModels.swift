import SwiftUI

@Observable
final class LoginViewModel {
    var email = ""
    var password = ""
    private(set) var isLoading = false
    var errorMessage: String?

    var resetMessage: String?
    private(set) var isGoogleLoading = false
    private let login: LoginUseCase
    private let auth: AuthRepository?
    private let googleLogin: GoogleLoginUseCase?
    init(login: LoginUseCase, auth: AuthRepository? = nil, googleLogin: GoogleLoginUseCase? = nil) {
        self.login = login; self.auth = auth; self.googleLogin = googleLogin
    }

    var canUseGoogle: Bool { googleLogin != nil && !isLoading && !isGoogleLoading }

    /// nil = cancelled or failed (errorMessage set on failure).
    func signInWithGoogle() async -> User? {
        guard let googleLogin, !isGoogleLoading else { return nil }
        isGoogleLoading = true; defer { isGoogleLoading = false }
        errorMessage = nil
        do { return try await googleLogin() }
        catch { errorMessage = error.localizedDescription; return nil }
    }

    func forgotPassword() async {
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard Validators.email(email) else { errorMessage = "Escribe tu correo arriba para enviarte el enlace"; return }
        do {
            try await auth?.forgotPassword(email: email)
            resetMessage = "Si \(email) tiene una cuenta, te enviamos un enlace para cambiar la contraseña."
        } catch { errorMessage = error.localizedDescription }
    }

    var canSubmit: Bool { !email.isEmpty && !password.isEmpty && !isLoading && !isGoogleLoading }

    func submit() async -> User? {
        isLoading = true; defer { isLoading = false }
        errorMessage = nil
        do { return try await login(email: email, password: password) }
        catch { errorMessage = error.localizedDescription; return nil }
    }
}

@Observable
final class RegisterViewModel {
    var firstName = ""
    var lastName = ""
    var email = ""
    var password = ""
    var confirm = ""
    private(set) var isLoading = false
    var errorMessage: String?

    private let register: RegisterUseCase
    init(register: RegisterUseCase) { self.register = register }

    var passwordsMatch: Bool { confirm.isEmpty || password == confirm }
    var canSubmit: Bool { !email.isEmpty && password.count >= 8 && password == confirm && !firstName.isEmpty && !lastName.isEmpty && !isLoading }

    func submit() async -> User? {
        isLoading = true; defer { isLoading = false }
        errorMessage = nil
        do { return try await register(email: email, password: password, firstName: firstName, lastName: lastName) }
        catch { errorMessage = error.localizedDescription; return nil }
    }
}

@Observable
final class LockViewModel {
    var pin = ""
    var errorMessage: String?
    private(set) var isAuthenticating = false
    private let biometrics: BiometricAuthenticator
    private let settings: SettingsRepository

    init(biometrics: BiometricAuthenticator, settings: SettingsRepository) { self.biometrics = biometrics; self.settings = settings }

    var hasPIN: Bool { settings.hasPIN }
    var biometryName: String { biometrics.biometryName }

    func authenticate() async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true; defer { isAuthenticating = false }
        return await biometrics.authenticate(reason: "Desbloquea Vexia")
    }

    func verifyPIN() -> Bool {
        if settings.verifyPIN(pin) { return true }
        errorMessage = "PIN incorrecto"; pin = ""
        return false
    }
}
