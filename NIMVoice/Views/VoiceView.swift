import SwiftUI

/// The primary, minimal, hands-free screen: animated background, central orb,
/// optional captions, and a thin control bar. No chat bubbles by default.
struct VoiceView: View {
    @Environment(VoiceSessionViewModel.self) private var session
    @Environment(SpeechRecognizer.self) private var recognizer
    @Environment(SettingsStore.self) private var settings

    @State private var showSettings = false
    @State private var showModels = false
    @State private var showHistory = false
    @State private var showCamera = false

    var body: some View {
        ZStack {
            AnimatedBackground(state: session.state)

            VStack {
                topBar
                Spacer()
                orbSection
                Spacer()
                if settings.captionsEnabled {
                    captions
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if session.pendingImage != nil {
                    attachedImageBar
                        .transition(.scale.combined(with: .opacity))
                }
                controlBar
            }
            .padding()

            if session.state.isError, let message = session.errorMessage {
                errorBanner(message)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await session.startSession()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showModels) {
            ModelBrowserView()
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: { session.resumeListening() }) {
            ImagePicker(source: .camera) { image in
                session.attachImage(image)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Attached image

    private var attachedImageBar: some View {
        HStack(spacing: 12) {
            if let image = session.pendingImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo attached")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text(session.activeModelSupportsVision
                     ? "Ask a question about it"
                     : "Tip: pick a vision model in Models")
                    .font(.caption)
                    .foregroundStyle(session.activeModelSupportsVision ? .white.opacity(0.6) : .orange)
            }
            Spacer()
            Button {
                session.clearPendingImage()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .accessibilityLabel("Remove photo")
        }
        .padding(12)
        .background(.ultraThinMaterial.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 8)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Menu {
                Button {
                    showHistory = true
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                Button {
                    startNewConversation()
                } label: {
                    Label("New conversation", systemImage: "plus.bubble")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // Active model chip — subtle, tappable to open the browser.
            Button {
                showModels = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                    Text(activeModelName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
            }
        }
    }

    // MARK: - Orb

    private var orbSection: some View {
        VStack(spacing: 24) {
            OrbView(state: session.state, level: session.orbLevel, muted: session.isMuted)
                .contentShape(Circle())
                .onTapGesture { session.handleOrbTap() }

            Text(session.isMuted ? "Muted" : session.state.label)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.75))
                .animation(.easeInOut, value: session.state)
                .accessibilityLabel(session.isMuted ? "Muted" : session.state.label)
        }
    }

    // MARK: - Captions

    private var captions: some View {
        VStack(spacing: 12) {
            if session.state == .listening, !recognizer.transcript.isEmpty {
                captionLine(text: recognizer.transcript, label: "You", emphasized: true)
            } else if !session.liveTranscript.isEmpty, session.state != .speaking {
                captionLine(text: session.liveTranscript, label: "You", emphasized: false)
            }
            if !session.lastReply.isEmpty {
                captionLine(text: session.lastReply, label: "Assistant", emphasized: session.state == .speaking)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.bottom, 8)
    }

    private func captionLine(text: String, label: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.45))
            Text(text)
                .font(.callout)
                .foregroundStyle(.white.opacity(emphasized ? 0.95 : 0.7))
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 16) {
            controlButton(
                symbol: session.isMuted ? "mic.slash.fill" : "mic.fill",
                tint: session.isMuted ? .red : .white,
                label: session.isMuted ? "Unmute" : "Mute"
            ) {
                session.toggleMute()
            }

            controlButton(
                symbol: "camera.fill",
                tint: session.activeModelSupportsVision ? .accentColor : .white,
                label: "Camera"
            ) {
                session.suspendListening()
                showCamera = true
            }

            controlButton(
                symbol: "globe",
                tint: settings.webSearchEnabled ? .accentColor : .white,
                label: settings.webSearchEnabled ? "Web search on" : "Web search off"
            ) {
                withAnimation(.spring(response: 0.4)) { settings.webSearchEnabled.toggle() }
                Haptics.tap()
            }

            controlButton(symbol: "captions.bubble", tint: settings.captionsEnabled ? .accentColor : .white, label: "Captions") {
                withAnimation(.spring(response: 0.4)) { settings.captionsEnabled.toggle() }
            }

            controlButton(symbol: "xmark", tint: .white, label: "End") {
                endSession()
            }
        }
        .padding(.top, 8)
    }

    private func controlButton(symbol: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(.white.opacity(0.12), in: Circle())
        }
        .accessibilityLabel(label)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal)
            .padding(.bottom, 120)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Actions

    private var activeModelName: String {
        session.activeModelID.split(separator: "/").last.map(String.init) ?? session.activeModelID
    }

    private func startNewConversation() {
        session.conversations.startNewConversation(systemPrompt: settings.systemPrompt, modelID: session.activeModelID)
        session.lastReply = ""
    }

    private func endSession() {
        session.endSession()
    }
}
