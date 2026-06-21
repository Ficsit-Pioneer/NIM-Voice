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
    /// True when this user turn included a captured image (for transcript display).
    /// The image bytes themselves are not persisted — they're passed straight to
    /// the model at request time.
    var hasImage: Bool

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date(), hasImage: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.hasImage = hasImage
    }

    // Backward-compatible decoding: conversations saved before `hasImage` existed
    // simply default it to false instead of failing to load.
    enum CodingKeys: String, CodingKey { case id, role, content, timestamp, hasImage }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(Role.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        hasImage = try c.decodeIfPresent(Bool.self, forKey: .hasImage) ?? false
    }
}

/// Tunable generation parameters sent with every chat completion request.
struct GenerationParams: Codable, Hashable, Sendable {
    var temperature: Double
    var topP: Double
    var maxTokens: Int

    static let `default` = GenerationParams(temperature: 0.7, topP: 1.0, maxTokens: 1024)
}
