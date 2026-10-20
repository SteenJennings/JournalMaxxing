import Foundation
import Speech
import AVFoundation

/// On-device live transcription behind a small concrete API, so the engine
/// can be swapped later (SpeechAnalyzer in iOS 26, or WhisperKit) by changing
/// TodayView's service, not its UI.
///
/// Engine used here: SFSpeechRecognizer with requiresOnDeviceRecognition
/// when the device supports it - stable, built-in, free. Known limit: the
/// legacy Speech framework caps a single recognition task at roughly a
/// minute of audio, which fits a journal entry; the task restarts are the
/// first thing the SpeechAnalyzer migration removes.
@MainActor
final class SpeechTranscriberService: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isRecording { stop() } else { Task { await start() } }
    }

    func start() async {
        errorMessage = nil
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer is not available right now."
            return
        }
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { errorMessage = "Speech recognition permission was not granted."; return }
        let micOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard micOK else { errorMessage = "Microphone permission was not granted."; return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition {
                req.requiresOnDeviceRecognition = true
            }
            request = req
            transcript = ""

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
                req?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal { self.stop() }
                    } else if error != nil, self.isRecording {
                        self.errorMessage = "Transcription stopped. You can type or try again."
                        self.stop()
                    }
                }
            }
            isRecording = true
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
