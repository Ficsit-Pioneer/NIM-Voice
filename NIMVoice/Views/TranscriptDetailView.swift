import SwiftUI
import UIKit

/// Full text transcript of a conversation. Even though the main screen is
/// minimal, this gives the user the complete history with copy & share.
struct TranscriptDetailView: View {
    let conversation: Conversation

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if conversation.visibleMessages.isEmpty {
                    Text("No messages in this conversation yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
                ForEach(conversation.visibleMessages) { message in
                    bubble(message)
                }
            }
            .padding()
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: conversation.transcriptText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "You" : "Assistant")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(message.content)
                    .font(.body)
                    .padding(12)
                    .background(
                        isUser ? AnyShapeStyle(Color.accentColor.opacity(0.85))
                               : AnyShapeStyle(.ultraThinMaterial),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .foregroundStyle(isUser ? Color.white : Color.primary)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
