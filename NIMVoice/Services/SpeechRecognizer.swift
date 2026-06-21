import Foundation
import Speech
import AVFoundation
import Observation

enum SpeechRecognizerError: LocalizedError {
    case notAuthorized
    case unavailable
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Microphone or speech permission was denied."
        case .unavailable: return "Speech recognition isn't available right now."
        case .engineFailed(let m): return "Couldn't start the microphone: \(m)"
        }
    }
}

/// `@Observable` wrapper over `SFSpeechRecognizer` + `AVAudioEngine`.
///
/// Responsibilities:
/// - Publish the live `transcript`, a smoothed `audioLevel` (for the orb), and
///   `isListening`.
/// - Perform **silence-based endpointing**: a timer is (re)armed on every
///   partial result; when it fires after ~`silenceTimeout` of no new speech,
///   the utterance is finalized and `onEndpoint` is called with the text.
@MainActor
@Observable
final class SpeechRecognizer {

    // Observed UI state.
    var transcript: String = ""
    var audioLevel: Float = 0            // 0...1, smoothed mic power for the orb
    var isListening: Bool = false
    var isAvailable: Bool = false
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    // Engine internals (ignored by Observation).
    @ObservationIgnored private let recognizer: SFSpeechRecognizer?
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTimer: Timer?
    @ObservationIgnored private var silenceTimeout: TimeInterval = 1.4
    @ObservationIgnored private var onEndpoint: ((String) -> Void)?
    @ObservationIgnored private var heardSpeech = false
    // Bumped on every start/stop so late callbacks from a canceled task that
    // belong to a previous session are ignored.
    @ObservationIgnored private var generation = 0

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        isAvailable = recognizer?.isAvailable ?? false
    }

    // MARK: - Authorization

    /// Requests both Speech Recognition and Microphone permission.
    func requestAuthorization() async -> Bool {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationStatus = speechStatus

        let micGranted: Bool = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        isAvailable = recognizer?.isAvailable ?? false
        return speechStatus == .authorized && micGranted
    }

    // MARK: - Listening

    /// Starts a fresh recognition session. The silence timer is only armed once
    /// speech is actually detected, so a quiet user never auto-endpoints.
    func start(silenceTimeout: TimeInterval, onEndpoint: @escaping (String) -> Void) throws {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else { throw SpeechRecognizerError.unavailable }
        guard authorizationStatus == .authorized else { throw SpeechRecognizerError.notAuthorized }

        self.silenceTimeout = silenceTimeout
        self.onEndpoint = onEndpoint
        transcript = ""
        heardSpeech = false
        generation &+= 1
        let gen = generation

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer on-device recognition for privacy + lower latency when supported.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        // Capture `request` locally (not `self.request`) so this realtime-thread
        // closure never touches main-actor state synchronously. Level updates are
        // hopped to the main actor via a Task.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = SpeechRecognizer.normalizedPower(from: buffer)
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                self.audioLevel = self.audioLevel * 0.82 + level * 0.18
            }
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Extract Sendable values before hopping; recognition callbacks
            // arrive on an internal queue.
            let text = result?.bestTranscription.formattedString
            let failed = error != nil
            Task { @MainActor in
                // Ignore stale callbacks from a canceled previous session.
                guard let self, self.generation == gen else { return }
                if let text {
                    self.transcript = text
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.heardSpeech = true
                        self.armSilenceTimer()
                    }
                }
                if failed, self.isListening {
                    // A surfaced error usually means the session ended; finalize.
                    self.endpoint()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            cleanupEngine()
            throw SpeechRecognizerError.engineFailed(error.localizedDescription)
        }
        isListening = true
    }

    /// Stops listening and tears down the engine without firing `onEndpoint`.
    func stop() {
        generation &+= 1            // invalidate any in-flight callbacks
        silenceTimer?.invalidate()
        silenceTimer = nil
        cleanupEngine()
        isListening = false
        audioLevel = 0
    }

    // MARK: - Endpointing

    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.endpoint() }
        }
    }

    /// Finalizes the current utterance and notifies the listener exactly once.
    private func endpoint() {
        guard isListening else { return }
        let finalText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = onEndpoint
        stop()
        callback?(finalText)
    }

    private func cleanupEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    // MARK: - Level metering

    /// RMS power of a buffer mapped to a friendly 0...1 range for the orb.
    nonisolated private static func normalizedPower(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        let db = 20 * log10(max(rms, 1e-7))      // ~ -∞...0 dB
        let minDb: Float = -50
        let clamped = max(minDb, min(db, 0))
        return (clamped - minDb) / (-minDb)       // -50dB→0, 0dB→1
    }
}
