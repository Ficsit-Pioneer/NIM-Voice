import SwiftUI

/// Lists past conversations. Tap to view the full transcript; swipe to delete;
/// resume to continue a session, or start a new one.
struct HistoryView: View {
    @Environment(ConversationStore.self) private var conversations
    @Environment(VoiceSessionViewModel.self) private var session
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if conversations.conversations.isEmpty {
                    ContentUnavailableView("No conversations yet",
                                           systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Your voice sessions will appear here."))
                } else {
                    list
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        newConversation()
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(conversations.conversations) { conversation in
                NavigationLink {
                    TranscriptDetailView(conversation: conversation)
                } label: {
                    row(conversation)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        conversations.delete(conversation)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        resume(conversation)
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .tint(.green)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                if conversation.id == conversations.currentID {
                    Text("Active")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            Text(conversation.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func resume(_ conversation: Conversation) {
        conversations.resume(conversation)
        Haptics.tap()
        dismiss()
    }

    private func newConversation() {
        conversations.startNewConversation(systemPrompt: settings.systemPrompt, modelID: session.activeModelID)
        session.lastReply = ""
        Haptics.tap()
        dismiss()
    }
}
