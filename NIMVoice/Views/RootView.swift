import SwiftUI

/// Chooses between onboarding and the main voice experience.
struct RootView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        if hasOnboarded {
            VoiceView()
                .transition(.opacity)
        } else {
            OnboardingView(onFinished: { withAnimation { hasOnboarded = true } })
                .transition(.opacity)
        }
    }
}

#Preview {
    RootView()
        .environment(SettingsStore())
        .environment(ConversationStore())
        .environment(SpeechRecognizer())
        .environment(SpeechSynthesizer())
        .environment(
            VoiceSessionViewModel(
                recognizer: SpeechRecognizer(),
                synthesizer: SpeechSynthesizer(),
                client: .shared,
                settings: SettingsStore(),
                conversations: ConversationStore()
            )
        )
}
