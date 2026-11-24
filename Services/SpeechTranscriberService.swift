import Foundation
import Speech
import AVFoundation

enum SpeechDownloadError: Error { case timeout }

/// On-device live transcription.
///
/// Engine: SpeechAnalyzer + SpeechTranscriber (iOS 26 Speech framework).
/// Runs entirely on-device with a system-managed model - nothing to bundle,
/// no network, no cost. Public API (transcript / isRecording / errorMessage /
/// toggle / start / stop) matches what TodayView already uses, so swapping
/// engines never touches the UI.
///
/// Flow: mic -> AVAudioEngine tap -> format conversion to the analyzer's
/// preferred format -> AnalyzerInput stream -> SpeechTranscriber.results.
/// Final results accumulate; volatile (partial) results show live.
@MainActor
final class SpeechTranscriberService: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?
    /// Shown while starting (e.g. while the speech model downloads).
    @Published var statusMessage: String?

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private let audioEngine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var finalText: String = ""
    private var volatileText: String = ""
    /// Guards the async start window: permissions + a possible model
    /// download take seconds, during which isRecording is still false and
    /// a second tap would install a second audio tap (a hard crash in
    /// AVAudioEngine) or start a competing analyzer.
    @Published private(set) var isStarting = false
    private var startGeneration = 0
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    init() {
        // A phone call or Siri used to kill the recording with no
        // message and leave the UI stuck on "Listening". Stop cleanly
        // and say why.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                guard let info = note.userInfo,
                      let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeRaw),
                      type == .began else { return }
                self.errorMessage = "Recording paused — interrupted (call or Siri). Tap the mic to resume."
                Log.event("Speech", "interruption began - stopped recording")
                self.stop()
            }
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                guard let info = note.userInfo,
                      let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw),
                      reason == .oldDeviceUnavailable else { return }
                self.errorMessage = "Recording paused — the microphone was disconnected. Tap the mic to resume."
                Log.event("Speech", "audio route lost (old device unavailable) - stopped recording")
                self.stop()
            }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeChangeObserver { NotificationCenter.default.removeObserver(routeChangeObserver) }
    }

    /// One-line, human-readable availability for the Data tab — the old
    /// row was a hardcoded string, so the tab claimed transcription was
    /// ready even when the locale check would fail.
    static func availabilitySummary() async -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            return "Speech recognition permission not granted"
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            return "Not available for \(Locale.current.identifier)"
        }
        return "Available (\(locale.identifier), on-device)"
    }

    /// Clear the error banner and any captured text (day rollover, day
    /// switch, manual dismiss). Does not touch a live recording.
    func clearAll() {
        errorMessage = nil
        statusMessage = nil
        guard !isRecording else { return }
        transcript = ""
        finalText = ""
        volatileText = ""
    }

    func toggle() {
        if isRecording || isStarting { stop() } else { Task { await start() } }
    }

    func start() async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        let generation = startGeneration
        defer { if generation == startGeneration { isStarting = false } }
        // F3: reset text state up front. Results can only arrive after the
        // engine starts, but resetting late risks wiping an early result.
        finalText = ""
        volatileText = ""
        transcript = ""
        errorMessage = nil
        statusMessage = nil
        // Permissions: speech recognition + microphone.
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { errorMessage = "Speech recognition permission was not granted."; Log.event("Speech", "speech recognition permission DENIED"); return }
        let micOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard micOK else { errorMessage = "Microphone permission was not granted."; Log.event("Speech", "microphone permission DENIED"); return }
        guard generation == startGeneration else { Log.event("Speech", "start aborted (stopped during setup)"); return }

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            errorMessage = "Speech transcription is not available for your language/region yet."
            Log.event("Speech", "no supported transcription locale equivalent to \(Locale.current.identifier) - unavailable (common in simulators)")
            return
        }
        Log.event("Speech", "transcription locale supported: \(locale.identifier)")

        do {
            let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            transcriber = module

            // The transcription model is a system asset; download it if the
            // device does not have it yet (one-time, system-managed). The
            // old code awaited this forever with no message and no
            // timeout — a stalled download looked like a dead mic.
            if let installRequest = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                Log.event("Speech", "transcription model asset not present - downloading")
                statusMessage = "Downloading speech model…"
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask { try await installRequest.downloadAndInstall() }
                        group.addTask {
                            try await Task.sleep(for: .seconds(60))
                            throw SpeechDownloadError.timeout
                        }
                        try await group.next()
                        group.cancelAll()
                    }
                    Log.event("Speech", "transcription model asset installed")
                } catch {
                    statusMessage = nil
                    errorMessage = "The speech model download timed out. Check your connection and try again."
                    Log.event("Speech", "model download failed/timed out: \(error.localizedDescription)")
                    return
                }
                statusMessage = nil
            }

            let session = SpeechAnalyzer(modules: [module])
            analyzer = session

            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                errorMessage = "No compatible audio format for transcription."
                Log.event("Speech", "no compatible audio format for transcription")
                return
            }
            try await session.prepareToAnalyze(in: format)
            guard generation == startGeneration else { Log.event("Speech", "start aborted (stopped during setup)"); return }

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            inputContinuation = continuation
            try await session.start(inputSequence: stream)

            // Live results. If the stream dies while recording, the old
            // code only set the banner and left the engine running with
            // a frozen "Listening" state — stop cleanly instead.
            resultsTask = Task { [weak self] in
                do {
                    for try await result in module.results {
                        let text = String(result.text.characters)
                        await MainActor.run {
                            guard let self else { return }
                            if result.isFinal {
                                self.finalText += text
                                self.volatileText = ""
                            } else {
                                self.volatileText = text
                            }
                            self.transcript = self.finalText + self.volatileText
                        }
                    }
                    await MainActor.run { [weak self] in
                        guard let self, self.isRecording else { return }
                        self.errorMessage = "Transcription stopped unexpectedly."
                        Log.event("Speech", "results stream ended while recording - stopped")
                        self.stop()
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.errorMessage = "Transcription stopped unexpectedly."
                        Log.event("Speech", "results stream error: \(error.localizedDescription)")
                        if self.isRecording { self.stop() }
                    }
                }
            }

            // Microphone -> analyzer, converting formats.
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let input = audioEngine.inputNode
            let micFormat = input.outputFormat(forBus: 0)
            converter = AVAudioConverter(from: micFormat, to: format)
            input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { [weak self] buffer, _ in
                guard let self, let converted = self.convert(buffer, to: format) else { return }
                self.inputContinuation?.yield(AnalyzerInput(buffer: converted))
            }
            audioEngine.prepare()
            try audioEngine.start()
            Log.event("Speech", "analyzer started (locale \(locale.identifier), format \(format.sampleRate)Hz)")
            isRecording = true
        } catch {
            errorMessage = "Could not start transcription: \(error.localizedDescription)"
            Log.event("Speech", "start failed: \(error.localizedDescription)")
            stop()
        }
    }

    func stop() {
        startGeneration += 1
        isStarting = false
        statusMessage = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        // Finish the input FIRST, then finalize the analyzer and let the
        // results task drain the remaining finals. The old code cancelled
        // the results task before finalizing, so the finalize call ran
        // after the consumer was gone and the last phrase was lost.
        inputContinuation?.finish()
        inputContinuation = nil
        let session = analyzer
        analyzer = nil
        transcriber = nil
        Log.event("Speech", "stopped (final transcript \(transcript.count) chars)")
        if let session {
            Task {
                try? await session.finalizeAndFinishThroughEndOfInput()
                // The results task ends on its own when the stream closes;
                // the watchdog only cancels one that is stuck.
                try? await Task.sleep(for: .seconds(2))
                self.resultsTask?.cancel()
                self.resultsTask = nil
                // Whatever drained in the meantime is the final text.
                self.transcript = self.finalText + self.volatileText
            }
        } else {
            resultsTask?.cancel()
            resultsTask = nil
        }
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Converts one mic buffer into the analyzer's format.
    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: out, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { return nil }
        return out
    }
}
