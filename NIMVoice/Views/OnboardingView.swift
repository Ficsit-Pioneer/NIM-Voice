import SwiftUI

/// A short, friendly permission + key intro shown once on first launch.
struct OnboardingView: View {
    let onFinished: () -> Void

    @Environment(SpeechRecognizer.self) private var recognizer
    @State private var permissionGranted = false
    @State private var requesting = false
    @State private var apiKeyDraft = ""
    @State private var validating = false
    @State private var keySaved = KeychainStore.hasKey

    var body: some View {
        ZStack {
            AnimatedBackground(state: .idle)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 40)

                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse)

                    VStack(spacing: 8) {
                        Text("NIM Voice")
                            .font(.largeTitle.bold())
                        Text("A hands-free voice conversation, powered by NVIDIA NIM.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)

                    VStack(spacing: 16) {
                        stepCard(
                            symbol: "mic.fill",
                            title: "Microphone & Speech",
                            subtitle: permissionGranted ? "Granted — you're all set." : "Used to hear and transcribe what you say, on-device.",
                            done: permissionGranted
                        ) {
                            Button(action: requestPermission) {
                                Text(permissionGranted ? "Granted" : "Allow access")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(permissionGranted || requesting)
                        }

                        stepCard(
                            symbol: "key.fill",
                            title: "NVIDIA API Key",
                            subtitle: keySaved ? "Saved to your Keychain." : "Paste your nvapi- key. You can also add it later in Settings.",
                            done: keySaved
                        ) {
                            VStack(spacing: 10) {
                                SecureField("nvapi-…", text: $apiKeyDraft)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)
                                Button(action: validateAndSaveKey) {
                                    if validating {
                                        ProgressView().frame(maxWidth: .infinity)
                                    } else {
                                        Text(keySaved ? "Update key" : "Validate & save")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(apiKeyDraft.isEmpty || validating)
                            }
                        }
                    }
                    .padding(.horizontal)

                    Button(action: onFinished) {
                        Text(keySaved ? "Start talking" : "Skip for now")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                    .disabled(!permissionGranted)

                    Text("Your key is stored only in the device Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 20)
                }
                .padding(.vertical)
            }
        }
        .task {
            permissionGranted = recognizer.authorizationStatus == .authorized
        }
    }

    @ViewBuilder
    private func stepCard<Content: View>(
        symbol: String,
        title: String,
        subtitle: String,
        done: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : symbol)
                    .font(.title2)
                    .foregroundStyle(done ? Color.green : Color.accentColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            content()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func requestPermission() {
        requesting = true
        Task {
            permissionGranted = await recognizer.requestAuthorization()
            requesting = false
        }
    }

    private func validateAndSaveKey() {
        validating = true
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let valid = await NIMClient.shared.validateKey(key)
            if valid {
                keySaved = KeychainStore.save(key)
                apiKeyDraft = ""
                Haptics.success()
            } else {
                Haptics.warning()
            }
            validating = false
        }
    }
}
