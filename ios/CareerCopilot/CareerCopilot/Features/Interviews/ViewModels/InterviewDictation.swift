import AVFoundation
import Combine
import Foundation
import Speech

enum DictationDraft {
    static func appending(_ transcript: String, to original: String) -> String {
        guard !transcript.isEmpty else { return original }
        guard !original.isEmpty else { return transcript }
        return original + (original.last?.isWhitespace == true ? "" : " ") + transcript
    }
}

@MainActor
final class InterviewDictation: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isPreparing = false
    @Published private(set) var isRecording = false
    @Published private(set) var isFinishing = false
    @Published private(set) var needsSettings = false
    @Published var error: String?

    var isActive: Bool { isPreparing || isRecording || isFinishing }
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var generation = UUID()
    private var audioSessionActive = false
    private var tapInstalled = false

    func start(locale: Locale = .current) async {
        guard !isActive else { return }
        let token = UUID()
        generation = token
        isPreparing = true
        error = nil
        needsSettings = false
        transcript = ""

        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard generation == token, !Task.isCancelled else { return }
        guard authorization == .authorized else {
            isPreparing = false
            needsSettings = authorization == .denied
            error = authorization == .restricted ? "Speech recognition is restricted on this device." : "Allow speech recognition in Settings to dictate your answer."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            isPreparing = false
            error = "On-device dictation is unavailable for the current language or device. You can type your answer instead."
            return
        }
        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        guard generation == token, !Task.isCancelled else { return }
        guard microphoneAllowed else {
            isPreparing = false
            needsSettings = true
            error = "Allow microphone access in Settings to dictate your answer."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            audioSessionActive = true
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationError.noAudioInput }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            self.audioEngine = engine
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal == true
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    if let text { self.transcript = text }
                    if isFinal { self.finish(cancelTask: false) }
                    else if failure != nil {
                        let hadText = !self.transcript.isEmpty
                        self.finish(cancelTask: true)
                        self.error = hadText ? "Dictation stopped. You can review and edit the text." : "Couldn’t transcribe audio. Try again or type your answer."
                    }
                }
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            isPreparing = false
            isRecording = true
        } catch {
            finish(cancelTask: true)
            self.error = "Couldn’t start dictation. Check your microphone and try again."
        }
    }

    func stop() {
        guard isRecording else { return }
        audioEngine?.stop()
        if tapInstalled { audioEngine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio()
        isRecording = false
        isFinishing = true
        let token = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.generation == token, self.isFinishing else { return }
            self.finish(cancelTask: true)
        }
    }

    func cancel() { finish(cancelTask: true) }

    private func finish(cancelTask: Bool) {
        generation = UUID()
        audioEngine?.stop()
        if tapInstalled { audioEngine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio()
        if cancelTask { recognitionTask?.cancel() }
        recognitionTask = nil
        request = nil
        audioEngine = nil
        isPreparing = false
        isRecording = false
        isFinishing = false
        if audioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActive = false
        }
    }

    private enum DictationError: Error { case noAudioInput }
}
