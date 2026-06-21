# NIM Voice

A hands-free, voice-first iOS assistant — **Mic → Apple STT → NVIDIA NIM (LLM) → Apple TTS → Speaker**, looping continuously like Claude / ChatGPT / Gemini voice mode. Built in pure SwiftUI with no third-party dependencies (Apple frameworks + `URLSession` only).

- Continuous, automatic turn-taking with silence-based endpointing (no push-to-talk).
- A glowing central orb that reacts to listening / thinking / speaking.
- Tap-to-interrupt (barge-in) while the assistant is speaking.
- In-app NVIDIA model browser (live NGC / NVIDIA API catalog).
- Conversation history, persisted locally.

> ⚠️ **Production note:** this app calls NVIDIA directly from the device with a key stored in the Keychain. That is fine for **personal / development** use. For a shipping product, route NIM calls through a backend proxy that holds the key — never embed it in a distributed client. (See the `TODO` in `NIMClient.swift`.)

---

## 1. Get a free NVIDIA API key

1. Go to **https://build.nvidia.com** and sign in / create a free NVIDIA Developer account.
2. Open any model (e.g. *llama-3.3-nemotron-super-49b*) and click **Get API Key** (sometimes shown as "Build with this NIM" → **Generate Key**).
3. Copy the key — it starts with **`nvapi-`**.

The same key works for both endpoints this app uses:
- `GET  https://integrate.api.nvidia.com/v1/models`
- `POST https://integrate.api.nvidia.com/v1/chat/completions`

## 2. Enter the key (stored in the Keychain)

The key is **never** hardcoded or stored in `UserDefaults`. On first launch:

1. Complete the short onboarding (grant **Microphone** + **Speech Recognition**).
2. Open **Settings** (gear icon, top-right of the voice screen).
3. Paste your `nvapi-…` key into **NVIDIA API Key** and tap **Validate** — this performs a live `GET /v1/models` call. On success the key is saved to the Keychain.

The key is stored in your **iCloud Keychain** (`kSecAttrSynchronizable`), so it **survives app reinstalls** and syncs privately across your own Apple ID devices — readable only by this app, invisible to everyone else. This needs iCloud Keychain enabled on the device (*Settings → [your name] → iCloud → Passwords and Keychain*), which is on by default for most users.

You can change or clear the key any time from Settings.

## 3. Run

> **No Mac?** You can still build and install this for free from Windows — a cloud
> macOS runner compiles it and you sideload with your own free Apple ID. See
> [SIDELOADING.md](SIDELOADING.md).

- Open `NIMVoice.xcodeproj` in **Xcode 16 or newer** (the project uses file-system-synchronized groups).
- Select an iOS 17+ simulator or a device, then **Run**.
- The microphone works best on a **real device**; the simulator can do speech recognition but mic quality varies.
- On a device, set your **Team** under *Signing & Capabilities* (the bundle id defaults to `com.nimvoice.app` — change it to something unique).

### Default model
Until you pick another in the model browser, the app uses:

```
nvidia/llama-3.3-nemotron-super-49b-v1
```

### Tests
Press **⌘U** in Xcode to run the unit tests (target `NIMVoiceTests`). They cover
`NIMClient` request/response decoding and error mapping (network-stubbed, no key
needed) and the `KeychainStore` round-trip (skips automatically if the keychain
isn't reachable in the run environment). A shared scheme is included, so the
project opens ready to build, run, and test.

---

## Required `Info.plist` keys

| Key | Purpose |
| --- | --- |
| `NSMicrophoneUsageDescription` | Microphone access for live speech input. |
| `NSSpeechRecognitionUsageDescription` | On-device speech-to-text. |
| `UIBackgroundModes` → `audio` | Keep mic/TTS alive briefly when the screen locks. |

All are included in [`NIMVoice/Info.plist`](NIMVoice/Info.plist).

---

## Architecture (MVVM)

| Type | Role |
| --- | --- |
| `SpeechRecognizer` | `@Observable` wrapper over `SFSpeechRecognizer` + `AVAudioEngine`; publishes live transcript, mic level (for the orb), and does silence-based endpointing. |
| `SpeechSynthesizer` | Wraps `AVSpeechSynthesizer`; publishes speaking state + progress + a per-word pulse; `stop()` for barge-in. |
| `NIMClient` | `actor` with `chat(messages:model:params:apiKey:)` (non-streaming) and `listModels(apiKey:)`. |
| `KeychainStore` | Secure API-key storage. |
| `AudioSessionManager` | Configures `AVAudioSession` so mic & speaker don't fight and the recognizer doesn't hear the AI. |
| `SettingsStore` | `@Observable`, autosaved preferences. |
| `ConversationStore` | `@Observable` history, JSON to Application Support. |
| `VoiceSessionViewModel` | Owns the state machine `idle → listening → thinking → speaking → listening`, mute, active model, and the orchestration loop. |

### The pipeline, in one breath
On launch the app requests permissions and **auto-starts listening**. Each partial transcription resets a ~1.4 s silence timer; when it fires, the utterance is finalized → the orb goes to **thinking** → a single non-streaming NIM call returns the full reply → it's spoken in one pass via TTS → the app **automatically returns to listening**. Tapping the orb while it speaks interrupts and re-opens the mic. No taps required for normal conversation.
