import SwiftUI

/// Voice / receipt → transaction draft.
@Observable
final class VexiaCaptureViewModel {
    enum Phase: Equatable { case idle, listening, thinking, review, error(String) }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var result: VexiaResult?
    private(set) var draft: TransactionDraft?
    var typedText = ""

    private let classify: ClassifyTransactionUseCase
    private let catalog: CatalogRepository
    private let transcriber: SpeechTranscriber
    private let language: String
    private var accounts: [Account] = []
    private var categories: [FinancialCategory] = []
    private var silenceTask: Task<Void, Never>?

    init(classify: ClassifyTransactionUseCase, catalog: CatalogRepository, transcriber: SpeechTranscriber, language: String) {
        self.classify = classify; self.catalog = catalog; self.transcriber = transcriber; self.language = language
    }

    func prepare() async {
        async let a = try? catalog.accounts()
        async let c = try? catalog.categories(type: nil)
        accounts = await a ?? []; categories = await c ?? []
    }

    func startListening() async {
        guard await transcriber.requestAuthorization() else {
            phase = .error("Activa los permisos de micrófono y reconocimiento de voz en Ajustes."); return
        }
        transcript = ""
        do {
            try transcriber.start(locale: Locale(identifier: language == "en" ? "en-US" : "es-ES")) { [weak self] text in
                self?.transcript = text
                self?.armSilenceTimer()
            }
            phase = .listening
        } catch { phase = .error(error.localizedDescription) }
    }

    /// Auto-stop after 2 s of silence.
    private func armSilenceTimer() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self?.phase == .listening else { return }
            await self?.stopAndProcess()
        }
    }

    func stopAndProcess() async {
        silenceTask?.cancel()
        guard phase == .listening else { return }
        let text = await transcriber.stop()
        transcript = text
        await process(text: text, image: nil)
    }

    func processTyped() async { await process(text: typedText, image: nil) }
    func processReceipt(_ jpeg: Data) async { await process(text: nil, image: jpeg) }

    private func process(text: String?, image: Data?) async {
        phase = .thinking
        do {
            let r = try await classify(text: text, imageJPEG: image, language: language, categories: categories, accounts: accounts)
            result = r
            draft = ClassifyTransactionUseCase.draft(from: r, accounts: accounts)
            phase = .review
        } catch { phase = .error(error.localizedDescription) }
    }

    var notes: [String] {
        guard let r = result else { return [] }
        return r.clarifyingQuestions.map(\.question) + r.warnings
    }

    func cancel() async {
        silenceTask?.cancel()
        if phase == .listening { _ = await transcriber.stop() }
        phase = .idle
    }
}
