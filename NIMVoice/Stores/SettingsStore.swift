import Foundation
import AVFoundation
import Observation

/// User preferences, observable and auto-persisted to `UserDefaults`.
///
/// Persistence note: `@Observable` doesn't support `didSet` on tracked
/// properties, so instead of per-property observers we register a single
/// `withObservationTracking` pass that calls `save()` whenever *any* tracked
/// property changes, then re-arms itself.
@MainActor
@Observable
final class SettingsStore {

    /// The model used until the user picks another from the browser.
    static let defaultModelID = "nvidia/llama-3.3-nemotron-super-49b-v1"

    static let defaultSystemPrompt = """
    You are a helpful, friendly voice assistant. Because your replies are spoken \
    aloud, keep them concise and conversational. Avoid markdown, lists, code \
    blocks, and emoji. Speak in short, natural sentences.
    """

    // MARK: Persisted preferences
    var systemPrompt: String
    var activeModelID: String
    var favoriteModelIDs: [String]
    var voiceIdentifier: String?
    var speechRate: Double          // AVSpeechUtterance rate (0.0...1.0)
    var pitch: Double               // pitch multiplier (0.5...2.0)
    var temperature: Double
    var topP: Double
    var maxTokens: Int
    var silenceTimeout: Double      // seconds of silence before endpointing
    var autoListen: Bool            // re-open mic automatically after each reply
    var captionsEnabled: Bool
    var webSearchEnabled: Bool      // ground answers with keyless web search
    var locationEnabled: Bool       // include approximate location in web search

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        systemPrompt = defaults.string(forKey: Keys.systemPrompt) ?? Self.defaultSystemPrompt
        activeModelID = defaults.string(forKey: Keys.activeModel) ?? Self.defaultModelID
        favoriteModelIDs = defaults.stringArray(forKey: Keys.favorites) ?? []
        voiceIdentifier = defaults.string(forKey: Keys.voice)
        speechRate = defaults.object(forKey: Keys.rate) as? Double ?? Double(AVSpeechUtteranceDefaultSpeechRate)
        pitch = defaults.object(forKey: Keys.pitch) as? Double ?? 1.0
        temperature = defaults.object(forKey: Keys.temperature) as? Double ?? GenerationParams.default.temperature
        topP = defaults.object(forKey: Keys.topP) as? Double ?? GenerationParams.default.topP
        maxTokens = defaults.object(forKey: Keys.maxTokens) as? Int ?? GenerationParams.default.maxTokens
        silenceTimeout = defaults.object(forKey: Keys.silenceTimeout) as? Double ?? 1.4
        autoListen = defaults.object(forKey: Keys.autoListen) as? Bool ?? true
        captionsEnabled = defaults.object(forKey: Keys.captions) as? Bool ?? false
        webSearchEnabled = defaults.object(forKey: Keys.webSearch) as? Bool ?? false
        locationEnabled = defaults.object(forKey: Keys.location) as? Bool ?? false

        isLoading = false
        observeAndPersist()
    }

    var generationParams: GenerationParams {
        GenerationParams(temperature: temperature, topP: topP, maxTokens: maxTokens)
    }

    // MARK: Favorites

    func isFavorite(_ modelID: String) -> Bool {
        favoriteModelIDs.contains(modelID)
    }

    func toggleFavorite(_ modelID: String) {
        if let index = favoriteModelIDs.firstIndex(of: modelID) {
            favoriteModelIDs.remove(at: index)
        } else {
            favoriteModelIDs.append(modelID)
        }
    }

    // MARK: Auto-persistence

    /// Re-arming observation pass: fires `save()` after any tracked change.
    private func observeAndPersist() {
        withObservationTracking {
            // Touch every persisted property so all are tracked.
            _ = (systemPrompt, activeModelID, favoriteModelIDs, voiceIdentifier,
                 speechRate, pitch, temperature, topP, maxTokens,
                 silenceTimeout, autoListen, captionsEnabled, webSearchEnabled,
                 locationEnabled)
        } onChange: { [weak self] in
            // onChange fires *before* the mutation commits, so defer to the next
            // main-actor turn to read the new values, then re-arm.
            Task { @MainActor [weak self] in
                self?.save()
                self?.observeAndPersist()
            }
        }
    }

    private func save() {
        guard !isLoading else { return }
        defaults.set(systemPrompt, forKey: Keys.systemPrompt)
        defaults.set(activeModelID, forKey: Keys.activeModel)
        defaults.set(favoriteModelIDs, forKey: Keys.favorites)
        if let voiceIdentifier {
            defaults.set(voiceIdentifier, forKey: Keys.voice)
        } else {
            defaults.removeObject(forKey: Keys.voice)
        }
        defaults.set(speechRate, forKey: Keys.rate)
        defaults.set(pitch, forKey: Keys.pitch)
        defaults.set(temperature, forKey: Keys.temperature)
        defaults.set(topP, forKey: Keys.topP)
        defaults.set(maxTokens, forKey: Keys.maxTokens)
        defaults.set(silenceTimeout, forKey: Keys.silenceTimeout)
        defaults.set(autoListen, forKey: Keys.autoListen)
        defaults.set(captionsEnabled, forKey: Keys.captions)
        defaults.set(webSearchEnabled, forKey: Keys.webSearch)
        defaults.set(locationEnabled, forKey: Keys.location)
    }

    private enum Keys {
        static let systemPrompt = "settings.systemPrompt"
        static let activeModel = "settings.activeModel"
        static let favorites = "settings.favorites"
        static let voice = "settings.voice"
        static let rate = "settings.rate"
        static let pitch = "settings.pitch"
        static let temperature = "settings.temperature"
        static let topP = "settings.topP"
        static let maxTokens = "settings.maxTokens"
        static let silenceTimeout = "settings.silenceTimeout"
        static let autoListen = "settings.autoListen"
        static let captions = "settings.captions"
        static let webSearch = "settings.webSearch"
        static let location = "settings.location"
    }
}
