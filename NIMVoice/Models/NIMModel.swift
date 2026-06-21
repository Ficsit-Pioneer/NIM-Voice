import Foundation

/// A coarse grouping derived from a model id, used to organize the browser.
enum ModelCategory: String, CaseIterable, Identifiable, Sendable {
    case chat = "Chat & Reasoning"
    case vision = "Vision & Multimodal"
    case code = "Code"
    case embedding = "Embeddings"
    case reranking = "Reranking"
    case safety = "Safety & Guard"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .vision: return "eye.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .embedding: return "point.3.connected.trianglepath.dotted"
        case .reranking: return "arrow.up.arrow.down"
        case .safety: return "shield.lefthalf.filled"
        case .other: return "cube.fill"
        }
    }
}

/// One entry from `GET /v1/models` (OpenAI-compatible catalog).
struct NIMModel: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let object: String?
    let created: Int?
    let ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }

    init(id: String, object: String? = nil, created: Int? = nil, ownedBy: String? = nil) {
        self.id = id
        self.object = object
        self.created = created
        self.ownedBy = ownedBy
    }

    /// The portion after the vendor prefix, e.g. `llama-3.3-nemotron-super-49b-v1`.
    var displayName: String {
        id.split(separator: "/").last.map(String.init) ?? id
    }

    /// The vendor prefix, e.g. `nvidia`, `meta`, `mistralai`.
    var vendor: String? {
        guard id.contains("/") else { return ownedBy }
        return id.split(separator: "/").first.map(String.init)
    }

    /// Best-effort categorization from keywords in the id.
    var category: ModelCategory {
        let lower = id.lowercased()
        if lower.contains("embed") || lower.contains("embedding") { return .embedding }
        if lower.contains("rerank") { return .reranking }
        if lower.contains("guard") || lower.contains("safety") || lower.contains("shield") || lower.contains("nemoguard") { return .safety }
        if lower.contains("vision") || lower.contains("-vl") || lower.contains("vlm") || lower.contains("vila") || lower.contains("image") || lower.contains("ocr") { return .vision }
        if lower.contains("code") || lower.contains("coder") || lower.contains("starcoder") { return .code }
        return .chat
    }

    /// Whether this model is plausibly usable with `/chat/completions`.
    var isChatCapable: Bool {
        switch category {
        case .embedding, .reranking: return false
        default: return true
        }
    }
}
