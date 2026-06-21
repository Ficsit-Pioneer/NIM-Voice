import Foundation

/// A chat role, matching the OpenAI-compatible wire format used by NVIDIA NIM.
enum Role: String, Codable, Hashable, Sendable {
    case system
    case user
    case assistant
}

/// A single message in a conversation. Doubles as the on-disk model and the
/// in-memory model; `NIMClient` maps it to the minimal `{role, content}` wire DTO.
struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var role: Role
    var content: String
    var timestamp: Date

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// Tunable generation parameters sent with every chat completion request.
struct GenerationParams: Codable, Hashable, Sendable {
    var temperature: Double
    var topP: Double
    var maxTokens: Int

    static let `default` = GenerationParams(temperature: 0.7, topP: 1.0, maxTokens: 1024)
}
