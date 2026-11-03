import AppIntents

/// Tells Siri what the user does inside the app, so it can suggest the matching shortcut at the
/// right time (lock screen, Spotlight). Siri-run intents donate themselves; only UI actions go here.
enum SiriDonations {
    /// New movement saved from the form or the Vexia AI confirmation (edits are not a habit to learn).
    static func transactionRegistered() {
        Task { _ = try? await IntentDonationManager.shared.donate(intent: RegisterTransactionIntent()) }
    }
}
