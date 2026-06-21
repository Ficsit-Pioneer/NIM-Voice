import Foundation
import Observation
import UIKit

/// Owns the voice state machine and the hands-free orchestration loop:
///
///   listening → (endpoint) → thinking → (NIM reply) → speaking → listening …
///
/// Also handles mute, barge-in, the active model, and error recovery.
@MainActor
@Observable
final class VoiceSessionViewModel {

    var state: VoiceState = .idle
    var isMuted = false
    var liveTranscript = ""          // what the user is currently saying
    var lastReply = ""               // the most recent assistant reply (for captions)
    var errorMessage: String?        // transient, surfaced subtly in the UI

    var activeModelID: String

    /// A captured image awaiting the next spoken question (thumbnail for the UI).
    var pendingImage: UIImage?
    @ObservationIgnored private var pendingImageBase64: String?

    /// Whether the active model is categorized as vision/multimodal.
    var activeModelSupportsVision: Bool {
        NIMModel(id: activeModelID).category == .vision
    }

    // Dependencies (not observed).
    @ObservationIgnored let recognizer: SpeechRecognizer
    @ObservationIgnored let synthesizer: SpeechSynthesizer
    @ObservationIgnored let client: NIMClient
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let conversations: ConversationStore

    @ObservationIgnored private var isSessionActive = false
    @ObservationIgnored private var errorRecoveryTask: Task<Void, Never>?

    init(
        recognizer: SpeechRecognizer,
        synthesizer: SpeechSynthesizer,
        client: NIMClient,
        settings: SettingsStore,
        conversations: ConversationStore
    ) {
        self.recognizer = recognizer
        self.synthesizer = synthesizer
        self.client = client
        self.settings = settings
        self.conversations = conversations
        self.activeModelID = settings.activeModelID
    }

    /// Drives the orb. Combines mic level (listening) with speech pulse (speaking).
    /// Reads the underlying observable services so SwiftUI re-renders on change.
    var orbLevel: Float {
        switch state {
        case .listening: return recognizer.audioLevel
        case .speaking: return max(0.3, synthesizer.speechPulse)
        case .thinking: return 0.22
        default: return 0
        }
    }

    var hasAPIKey: Bool { KeychainStore.hasKey }

    // MARK: - Session lifecycle

    /// Requests permissions, configures audio, ensures a conversation exists,
    /// then auto-starts listening. Safe to call repeatedly.
    func startSession() async {
        guard !isSessionActive else { return }

        let granted = await recognizer.requestAuthorization()
        guard granted else {
            state = .error("Microphone & Speech permission are needed. Enable them in iOS Settings.")
            return
        }
        guard KeychainStore.hasKey else {
            state = .error("Add your NVIDIA API key in Settings to begin.")
            return
        }

        do {
            try AudioSessionManager.configure()
        } catch {
            state = .error("Couldn't set up audio: \(error.localizedDescription)")
            return
        }

        if conversations.current == nil {
            conversations.startNewConversation(systemPrompt: settings.systemPrompt, modelID: activeModelID)
        }

        isSessionActive = true
        isMuted = false
        beginListening()
    }

    func endSession() {
        isSessionActive = false
        errorRecoveryTask?.cancel()
        recognizer.stop()
        synthesizer.stop()
        AudioSessionManager.deactivate()
        state = .idle
        liveTranscript = ""
    }

    // MARK: - Controls

    func toggleMute() {
        isMuted.toggle()
        Haptics.tap()
        if isMuted {
            recognizer.stop()
            if state == .listening { state = .idle }
        } else if isSessionActive {
            beginListening()
        }
    }

    // MARK: - Image attachment (vision)

    /// Compresses and stores a captured image to send with the next utterance.
    func attachImage(_ image: UIImage) {
        guard let base64 = ImageEncoder.jpegBase64(image, maxBytes: 130_000) else {
            errorMessage = "Couldn't process that image."
            return
        }
        pendingImage = image
        pendingImageBase64 = base64
        Haptics.tap()
    }

    func clearPendingImage() {
        pendingImage = nil
        pendingImageBase64 = nil
    }

    /// Pause/resume the mic around a modal (e.g. the camera) that needs focus.
    func suspendListening() {
        recognizer.stop()
        if state == .listening { state = .idle }
    }

    func resumeListening() {
        if isSessionActive, !isMuted, state != .thinking, state != .speaking {
            beginListening()
        }
    }

    /// Orb tap: barge-in while speaking, otherwise (re)start listening.
    func handleOrbTap() {
        switch state {
        case .speaking:
            synthesizer.stop()
            beginListening()
        case .idle, .error:
            if isSessionActive {
                isMuted = false
                beginListening()
            } else {
                Task { await startSession() }
            }
        case .listening, .thinking:
            break
        }
    }

    // MARK: - State machine

    private func beginListening() {
        guard isSessionActive, !isMuted else { return }
        errorRecoveryTask?.cancel()
        synthesizer.stop()
        liveTranscript = ""
        errorMessage = nil

        do {
            try recognizer.start(silenceTimeout: settings.silenceTimeout) { [weak self] text in
                self?.handleEndpoint(text)
            }
            state = .listening
            Haptics.soft()
        } catch {
            presentError(error, recover: true)
        }
    }

    /// Mirror the recognizer's live transcript into the view model for captions.
    func syncLiveTranscript() {
        if state == .listening {
            liveTranscript = recognizer.transcript
        }
    }

    private func handleEndpoint(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Heard nothing usable — quietly re-open the mic.
            if isSessionActive && !isMuted { beginListening() }
            return
        }
        liveTranscript = trimmed
        Task { await respond(to: trimmed) }
    }

    private func respond(to userText: String) async {
        state = .thinking
        Haptics.tap()

        // Consume any pending image exactly once for this turn.
        let image = pendingImageBase64
        clearPendingImage()
        conversations.append(ChatMessage(role: .user, content: userText, hasImage: image != nil))

        guard let apiKey = KeychainStore.read(), !apiKey.isEmpty else {
            presentError(NIMError.missingAPIKey, recover: false)
            return
        }

        // Optional keyless web search (+ page reading) to ground the answer.
        var searchContext: String? = nil
        if settings.webSearchEnabled {
            let place = settings.locationEnabled ? await LocationService.shared.placeDescription() : nil
            searchContext = await WebSearchService.shared.search(userText, location: place)
        }

        let history = conversations.current?.messages ?? []
        do {
            let reply = try await client.chat(
                messages: history,
                model: activeModelID,
                params: settings.generationParams,
                apiKey: apiKey,
                imageBase64: image,
                searchContext: searchContext
            )
            guard isSessionActive else { return }
            conversations.append(ChatMessage(role: .assistant, content: reply))
            lastReply = reply
            Haptics.success()
            speak(reply)
        } catch {
            presentError(error, recover: true)
        }
    }

    private func speak(_ text: String) {
        state = .speaking
        // Apply the chosen voice/rate/pitch right before speaking.
        synthesizer.voiceIdentifier = settings.voiceIdentifier
        synthesizer.rate = Float(settings.speechRate)
        synthesizer.pitch = Float(settings.pitch)

        synthesizer.speak(text) { [weak self] in
            guard let self, self.isSessionActive else { return }
            // Natural completion → auto-listen if enabled.
            if self.settings.autoListen && !self.isMuted {
                self.beginListening()
            } else {
                self.state = .idle
            }
        }
    }

    // MARK: - Active model

    func setActiveModel(_ modelID: String) {
        activeModelID = modelID
        settings.activeModelID = modelID
    }

    // MARK: - Errors

    /// Surfaces an error subtly and (optionally) auto-recovers to listening.
    private func presentError(_ error: Error, recover: Bool) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        errorMessage = message
        state = .error(message)
        Haptics.warning()

        guard recover else { return }
        errorRecoveryTask?.cancel()
        errorRecoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled, self.isSessionActive, !self.isMuted else { return }
            self.beginListening()
        }
    }
}
