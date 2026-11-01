import Foundation
import Speech
import AVFoundation

/// Speech framework adapter (on-device when supported).
final class AppleSpeechTranscriber: SpeechTranscriber {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var transcript = ""

    func requestAuthorization() async -> Bool {
        let speech = await Self.requestSpeechAuthorization()
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    func start(locale: Locale, onPartial: @escaping @MainActor (String) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw AIError.unavailable("reconocimiento de voz no disponible")
        }
        transcript = ""
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audio.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(req))
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: req, resultHandler: Self.resultHandler { [weak self] text in
            self?.transcript = text
            onPartial(text)
        })
    }

    // Callbacks below run on audio / Speech queues → must not inherit MainActor isolation.
    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    private nonisolated static func tapBlock(_ req: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in req.append(buffer) }
    }

    private nonisolated static func resultHandler(_ onText: @escaping @MainActor (String) -> Void) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in onText(text) }
        }
    }

    func stop() async -> String {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        try? await Task.sleep(for: .milliseconds(350)) // let the final result arrive
        task?.cancel()
        task = nil; request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return transcript
    }
}
