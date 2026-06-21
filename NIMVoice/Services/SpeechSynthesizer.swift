import Foundation
import AVFoundation
import Observation

/// `@Observable` wrapper over `AVSpeechSynthesizer`.
///
/// Speaks the whole reply in one pass (the LLM call is non-streaming, so the
/// full text is available). Publishes `isSpeaking`, a 0...1 `progress`, and a
/// per-word `speechPulse` that the orb uses to "undulate" in sync with speech.
/// `stop()` provides immediate barge-in.
@MainActor
@Observable
final class SpeechSynthesizer: NSObject {

    var isSpeaking = false
    var progress: Double = 0          // 0...1 across the current utterance
    var speechPulse: Float = 0        // momentary spike on each spoken word

    // Voice configuration (set by the view model from Settings before speaking).
    var voiceIdentifier: String?
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    var pitch: Float = 1.0

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var onFinish: (() -> Void)?
    @ObservationIgnored private var totalLength = 1

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text`, calling `onFinish` only on natural completion (not when
    /// interrupted via `stop()`).
    func speak(_ text: String, onFinish: @escaping () -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { onFinish(); return }

        self.onFinish = onFinish
        totalLength = max(text.count, 1)
        progress = 0

        let utterance = AVSpeechUtterance(string: text)
        if let id = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        }
        utterance.rate = rate
        utterance.pitchMultiplier = pitch

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Immediate barge-in. Suppresses the finish callback so the caller's own
    /// barge-in handler controls what happens next.
    func stop() {
        onFinish = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        speechPulse = 0
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            let spoken = characterRange.location + characterRange.length
            self.progress = min(1, Double(spoken) / Double(self.totalLength))
            // Pulse the orb on each spoken word for an organic, in-sync feel.
            self.speechPulse = Float.random(in: 0.55...1.0)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.progress = 1
            self.isSpeaking = false
            self.speechPulse = 0
            let callback = self.onFinish
            self.onFinish = nil
            callback?()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
            self.speechPulse = 0
            self.onFinish = nil    // canceled (barge-in) — don't auto-continue
        }
    }
}
