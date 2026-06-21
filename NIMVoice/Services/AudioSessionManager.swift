import Foundation
import AVFoundation

/// Centralizes `AVAudioSession` configuration.
///
/// Why this exists: the recognizer (mic input) and the synthesizer (speaker
/// output) share one audio route. We use `.playAndRecord` + `.spokenAudio` so
/// both can be active, `.duckOthers` so other audio lowers, and
/// `.defaultToSpeaker` so TTS is audible without headphones.
///
/// The recognizer transcribing the AI's *own* voice is avoided at a higher
/// level: `VoiceSessionViewModel` stops the recognizer before speaking and
/// restarts it afterwards, so the mic is never live while TTS plays.
enum AudioSessionManager {

    static func configure() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.duckOthers, .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )
        try session.setActive(true, options: [])
    }

    static func activate() throws {
        try AVAudioSession.sharedInstance().setActive(true, options: [])
    }

    /// Notifies other apps so their audio can resume (e.g. music that was ducked).
    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
