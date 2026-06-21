import SwiftUI

/// App entry point. Constructs the long-lived stores/services once and injects
/// them into the SwiftUI environment so every screen shares the same instances.
@main
struct NIMVoiceApp: App {

    // The shared, observable state of the app. Held as @State so SwiftUI keeps
    // them alive for the lifetime of the scene.
    @State private var settings: SettingsStore
    @State private var conversations: ConversationStore
    @State private var recognizer: SpeechRecognizer
    @State private var synthesizer: SpeechSynthesizer
    @State private var session: VoiceSessionViewModel

    @MainActor
    init() {
        // Build the dependency graph once. NIMClient is an actor singleton.
        // @MainActor because the stores/services are main-actor isolated.
        let settings = SettingsStore()
        let conversations = ConversationStore()
        let recognizer = SpeechRecognizer()
        let synthesizer = SpeechSynthesizer()
        let session = VoiceSessionViewModel(
            recognizer: recognizer,
            synthesizer: synthesizer,
            client: .shared,
            settings: settings,
            conversations: conversations
        )

        _settings = State(initialValue: settings)
        _conversations = State(initialValue: conversations)
        _recognizer = State(initialValue: recognizer)
        _synthesizer = State(initialValue: synthesizer)
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(conversations)
                .environment(recognizer)
                .environment(synthesizer)
                .environment(session)
        }
    }
}
