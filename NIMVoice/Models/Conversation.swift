import Foundation

/// A persisted conversation session. The first message is conventionally the
/// `.system` prompt; `visibleMessages` hides it from the transcript UI.
struct Conversation: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
    var modelID: String?

    init(
        id: UUID = UUID(),
        title: String = "New conversation",
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        modelID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelID = modelID
    }

    /// Messages shown in the transcript (everything except the system prompt).
    var visibleMessages: [ChatMessage] {
        messages.filter { $0.role != .system }
    }

    /// A short preview for the history list.
    var preview: String {
        let body = visibleMessages.last?.content ?? "No messages yet"
        return body.replacingOccurrences(of: "\n", with: " ")
    }

    /// Plain-text export used by copy / share.
    var transcriptText: String {
        visibleMessages.map { message in
            let speaker = message.role == .user ? "You" : "Assistant"
            return "\(speaker): \(message.content)"
        }
        .joined(separator: "\n\n")
    }
}
