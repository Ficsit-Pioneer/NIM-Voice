import SwiftUI
import AVFoundation

/// All user-tunable settings: API key (Keychain), system prompt, voice, speech
/// rate/pitch, generation params, endpointing sensitivity, and auto-listen.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyDraft = ""
    @State private var keyValidation: KeyValidation = .idle
    @State private var hasStoredKey = KeychainStore.hasKey

    private enum KeyValidation: Equatable {
        case idle, validating, valid, invalid
    }

    var body: some View {
        // Each section re-wraps the store with @Bindable to derive bindings.
        NavigationStack {
            Form {
                apiKeySection
                modelSection(settings: settings)
                promptSection(settings: settings)
                voiceSection(settings: settings)
                generationSection(settings: settings)
                listeningSection(settings: settings)
                webSection(settings: settings)
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - API key

    private var apiKeySection: some View {
        Section {
            SecureField(hasStoredKey ? "•••••••• (stored)" : "nvapi-…", text: $apiKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack {
                Button {
                    validateAndSave()
                } label: {
                    switch keyValidation {
                    case .validating: ProgressView()
                    default: Text(hasStoredKey ? "Update & validate" : "Validate & save")
                    }
                }
                .disabled(apiKeyDraft.isEmpty || keyValidation == .validating)

                Spacer()

                if hasStoredKey {
                    Button("Clear", role: .destructive) {
                        KeychainStore.delete()
                        hasStoredKey = false
                        keyValidation = .idle
                        apiKeyDraft = ""
                    }
                }
            }

            switch keyValidation {
            case .valid:
                Label("Key validated and saved.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).font(.caption)
            case .invalid:
                Label("That key was rejected by NVIDIA.", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red).font(.caption)
            default:
                EmptyView()
            }
        } header: {
            Text("NVIDIA API Key")
        } footer: {
            Text("Stored in your iCloud Keychain — it survives reinstalls and syncs privately to your own Apple ID devices. For production, proxy requests through your own backend instead of shipping a key.")
        }
    }

    // MARK: - Model

    private func modelSection(settings: SettingsStore) -> some View {
        Section("Active Model") {
            HStack {
                Image(systemName: "cpu")
                Text(settings.activeModelID)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            Text("Change this from the Models browser on the main screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - System prompt

    private func promptSection(settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return Section {
            TextEditor(text: $settings.systemPrompt)
                .frame(minHeight: 110)
                .font(.callout)
            Button("Reset to default") {
                settings.systemPrompt = SettingsStore.defaultSystemPrompt
            }
            .font(.caption)
        } header: {
            Text("System Prompt")
        } footer: {
            Text("Sets the assistant's behavior. Kept brief and speech-friendly by default.")
        }
    }

    // MARK: - Voice

    private func voiceSection(settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return Section {
            Picker("Voice", selection: Binding(
                get: { settings.voiceIdentifier ?? "" },
                set: { settings.voiceIdentifier = $0.isEmpty ? nil : $0 }
            )) {
                Text("System default").tag("")
                ForEach(availableVoices, id: \.identifier) { voice in
                    Text(voiceLabel(voice)).tag(voice.identifier)
                }
            }

            VStack(alignment: .leading) {
                Text("Speech rate").font(.caption).foregroundStyle(.secondary)
                Slider(
                    value: $settings.speechRate,
                    in: Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate)
                ) {
                    Text("Rate")
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
            }

            VStack(alignment: .leading) {
                Text("Pitch").font(.caption).foregroundStyle(.secondary)
                Slider(value: $settings.pitch, in: 0.5...2.0)
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("Premium and Enhanced voices sound the most natural. Download more in iOS Settings → Accessibility → Spoken Content → Voices and they'll appear here. (Apple doesn't allow third-party apps to use the actual Siri voice, but Premium voices are the same high quality.)")
        }
    }

    // MARK: - Generation

    private func generationSection(settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return Section {
            labeledSlider("Temperature", value: $settings.temperature, range: 0...2, spec: "%.2f")
            labeledSlider("Top-p", value: $settings.topP, range: 0...1, spec: "%.2f")
            Stepper(value: $settings.maxTokens, in: 64...8192, step: 64) {
                HStack {
                    Text("Max tokens")
                    Spacer()
                    Text("\(settings.maxTokens)").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Generation")
        } footer: {
            Text("Sent with every NIM request.")
        }
    }

    // MARK: - Listening

    private func listeningSection(settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Silence timeout")
                    Spacer()
                    Text(String(format: "%.1fs", settings.silenceTimeout)).foregroundStyle(.secondary)
                }
                Slider(value: $settings.silenceTimeout, in: 0.6...3.0, step: 0.1)
            }
            Toggle("Auto-listen after reply", isOn: $settings.autoListen)
            Toggle("Show captions", isOn: $settings.captionsEnabled)
        } header: {
            Text("Listening")
        } footer: {
            Text("Silence timeout controls how long a pause ends your turn. Lower is snappier; higher tolerates longer pauses.")
        }
    }

    private func webSection(settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Web search", isOn: $settings.webSearchEnabled)
            Toggle("Use my location", isOn: $settings.locationEnabled)
                .disabled(!settings.webSearchEnabled)
        } header: {
            Text("Web")
        } footer: {
            Text("When on, each question is looked up via DuckDuckGo + Wikipedia (no API key) and the top pages are read so the model sees real page content — great for facts, articles, and reference pages. Reading is limited for app-style sites (live menus, prices, maps) that render with JavaScript. \"Use my location\" adds your approximate city to searches so \"nearby\" questions have a reference point.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Endpoint", value: "integrate.api.nvidia.com")
            LabeledContent("Streaming", value: "Off (full reply spoken at once)")
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, spec: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: spec, value.wrappedValue)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    /// All installed voices, best quality first (Premium → Enhanced → Default),
    /// then grouped by language and name. Downloaded Premium/Enhanced voices —
    /// the "Siri-grade" ones — surface at the top.
    private var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted { a, b in
            if a.quality.rawValue != b.quality.rawValue {
                return a.quality.rawValue > b.quality.rawValue
            }
            if a.language != b.language { return a.language < b.language }
            return a.name < b.name
        }
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let base = "\(voice.name) — \(voice.language)"
        switch voice.quality {
        case .premium: return base + " · Premium"
        case .enhanced: return base + " · Enhanced"
        default: return base
        }
    }

    private func validateAndSave() {
        keyValidation = .validating
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let valid = await NIMClient.shared.validateKey(key)
            if valid {
                hasStoredKey = KeychainStore.save(key)
                keyValidation = .valid
                apiKeyDraft = ""
                Haptics.success()
            } else {
                keyValidation = .invalid
                Haptics.warning()
            }
        }
    }
}
