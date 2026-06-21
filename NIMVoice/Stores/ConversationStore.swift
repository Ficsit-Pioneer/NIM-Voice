import Foundation
import Observation

/// Owns the list of conversations and the "current" one. Persists everything as
/// JSON in Application Support. (SwiftData would also work here; plain Codable
/// keeps the model transparent and dependency-free.)
@MainActor
@Observable
final class ConversationStore {

    var conversations: [Conversation] = []
    var currentID: UUID?

    @ObservationIgnored private let fileURL: URL

    var current: Conversation? {
        guard let currentID else { return nil }
        return conversations.first { $0.id == currentID }
    }

    init() {
        let baseDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NIMVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        fileURL = baseDir.appendingPathComponent("conversations.json")
        load()
    }

    // MARK: - Mutations

    /// Begins a fresh conversation seeded with the system prompt and makes it current.
    @discardableResult
    func startNewConversation(systemPrompt: String, modelID: String) -> Conversation {
        let convo = Conversation(
            messages: [ChatMessage(role: .system, content: systemPrompt)],
            modelID: modelID
        )
        conversations.insert(convo, at: 0)
        currentID = convo.id
        save()
        return convo
    }

    /// Appends a message to the current conversation, updating its title/timestamp.
    func append(_ message: ChatMessage) {
        guard let index = conversations.firstIndex(where: { $0.id == currentID }) else { return }
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
        if message.role == .user, conversations[index].title == "New conversation" {
            let snippet = message.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(42)
            conversations[index].title = snippet.isEmpty ? "New conversation" : String(snippet)
        }
        save()
    }

    /// Clears the current conversation back to just its system prompt.
    func clearCurrent(systemPrompt: String) {
        guard let index = conversations.firstIndex(where: { $0.id == currentID }) else { return }
        conversations[index].messages = [ChatMessage(role: .system, content: systemPrompt)]
        conversations[index].title = "New conversation"
        conversations[index].updatedAt = Date()
        save()
    }

    func resume(_ conversation: Conversation) {
        currentID = conversation.id
    }

    func delete(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if currentID == conversation.id { currentID = conversations.first?.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { conversations[$0].id }
        conversations.remove(atOffsets: offsets)
        if let currentID, ids.contains(currentID) { self.currentID = conversations.first?.id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        if let saved = try? decoder.decode([Conversation].self, from: data) {
            conversations = saved.sorted { $0.updatedAt > $1.updatedAt }
            currentID = conversations.first?.id
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(conversations)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Persistence failures shouldn't crash the conversation; log only.
            print("ConversationStore save failed: \(error)")
        }
    }
}
