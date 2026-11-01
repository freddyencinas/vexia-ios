import Foundation

nonisolated enum ValidationError: LocalizedError, Equatable {
    case invalidEmail, shortPassword, missingName, invalidAmount, missingAccount, sameAccounts, missingCategory, missingSymbol
    var errorDescription: String? {
        switch self {
        case .invalidEmail: "Correo electrónico inválido"
        case .shortPassword: "La contraseña debe tener al menos 8 caracteres"
        case .missingName: "Nombre y apellido son obligatorios"
        case .invalidAmount: "El monto debe ser mayor a 0"
        case .missingAccount: "Selecciona una cuenta"
        case .sameAccounts: "Las cuentas de origen y destino deben ser distintas"
        case .missingCategory: "Selecciona una categoría"
        case .missingSymbol: "Ingresa el símbolo"
        }
    }
}

nonisolated enum Validators {
    static func email(_ s: String) -> Bool {
        s.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }
}

struct LoginUseCase {
    let repo: AuthRepository
    func callAsFunction(email: String, password: String) async throws -> User {
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard Validators.email(email) else { throw ValidationError.invalidEmail }
        guard !password.isEmpty else { throw ValidationError.shortPassword }
        return try await repo.login(email: email, password: password).user
    }
}

struct RegisterUseCase {
    let repo: AuthRepository
    func callAsFunction(email: String, password: String, firstName: String, lastName: String) async throws -> User {
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard Validators.email(email) else { throw ValidationError.invalidEmail }
        guard password.count >= 8 else { throw ValidationError.shortPassword }
        guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty,
              !lastName.trimmingCharacters(in: .whitespaces).isEmpty else { throw ValidationError.missingName }
        return try await repo.register(email: email, password: password, firstName: firstName, lastName: lastName).user
    }
}

/// Google ID token → POST /auth/google.
/// Returns nil when the user cancels the Google sheet.
struct GoogleLoginUseCase {
    let google: GoogleIdentityProvider
    let repo: AuthRepository
    func callAsFunction() async throws -> User? {
        guard let idToken = try await google.signIn() else { return nil }
        return try await repo.loginWithGoogle(idToken: idToken).user
    }
}

/// Cold-start session restore:
/// tokens? → refresh → (biometric gate) → /auth/me.
struct RestoreSessionUseCase {
    enum Outcome: Equatable { case authenticated(User), locked, unauthenticated }
    let repo: AuthRepository
    let settings: SettingsRepository

    func callAsFunction() async -> Outcome {
        guard repo.hasStoredSession else { return .unauthenticated }
        guard await repo.refreshSession() else { await repo.logout(); return .unauthenticated }
        if settings.biometricEnabled { return .locked }
        do { return .authenticated(try await repo.currentUser()) }
        catch { await repo.logout(); return .unauthenticated }
    }
}
