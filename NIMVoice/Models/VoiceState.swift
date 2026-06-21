import Foundation

/// The state machine that drives the orb and the orchestration loop:
/// `idle → listening → thinking → speaking → listening`.
enum VoiceState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error(String)

    /// Short label shown under the orb / used for accessibility.
    var label: String {
        switch self {
        case .idle: return "Tap to start"
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        case .error: return "Something went wrong"
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
