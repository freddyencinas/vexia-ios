import Foundation

nonisolated struct User: Identifiable, Hashable, Sendable {
    let id: String
    var email: String
    var firstName: String
    var lastName: String
    var isActive: Bool = true
    var isEmailVerified: Bool = false
    var subscriptionStatus: String = "free"

    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }
    var initials: String {
        let f = firstName.first.map(String.init) ?? ""
        let l = lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? String(email.prefix(1)).uppercased() : s
    }
    var hasActiveSubscription: Bool { ["active", "trial"].contains(subscriptionStatus) }
}

nonisolated struct AuthTokens: Hashable, Sendable {
    let accessToken: String
    let refreshToken: String
}

nonisolated struct AuthSession: Hashable, Sendable {
    let user: User
    let tokens: AuthTokens
}
