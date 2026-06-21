import Foundation

/// Errors surfaced from the NVIDIA NIM endpoints, with user-facing copy.
enum NIMError: LocalizedError {
    case missingAPIKey
    case unauthorized
    case emptyResponse
    case invalidResponse
    case http(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key. Add your NVIDIA key in Settings."
        case .unauthorized:
            return "Your API key was rejected. Check it in Settings."
        case .emptyResponse:
            return "The model returned an empty response."
        case .invalidResponse:
            return "Unexpected response from the server."
        case .http(let status, let message):
            if let message, !message.isEmpty {
                return "Request failed (\(status)): \(message)"
            }
            return "Request failed with status \(status)."
        }
    }
}

/// Talks to NVIDIA NIM's OpenAI-compatible API. Implemented as an `actor` so
/// network calls are serialized and isolated from the UI.
///
/// TODO (production): do NOT call NVIDIA directly from a distributed app. Route
/// these requests through your own backend proxy that holds the API key. The
/// in-app Keychain approach here is for personal / development use only.
actor NIMClient {
    static let shared = NIMClient()

    private let baseURL = URL(string: "https://integrate.api.nvidia.com/v1")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Chat completion (non-streaming)

    /// Sends the full message history and returns the complete assistant reply.
    /// `stream` is deliberately `false` so the reply can be spoken in one pass.
    func chat(
        messages: [ChatMessage],
        model: String,
        params: GenerationParams,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw NIMError.missingAPIKey }

        let url = baseURL.appendingPathComponent("chat/completions")
        let payload = ChatRequest(
            model: model,
            messages: messages.map { ChatRequest.Message(role: $0.role.rawValue, content: $0.content) },
            temperature: params.temperature,
            topP: params.topP,
            maxTokens: params.maxTokens,
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NIMError.emptyResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Model catalog

    /// Fetches the browsable model catalog from `GET /v1/models`.
    func listModels(apiKey: String) async throws -> [NIMModel] {
        guard !apiKey.isEmpty else { throw NIMError.missingAPIKey }

        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.sorted { $0.id.lowercased() < $1.id.lowercased() }
    }

    /// Lightweight key validation used by the Settings screen.
    func validateKey(_ apiKey: String) async -> Bool {
        do {
            _ = try await listModels(apiKey: apiKey)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NIMError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw NIMError.unauthorized
            }
            let message = Self.extractErrorMessage(from: data)
            throw NIMError.http(status: http.statusCode, message: message)
        }
    }

    /// Pulls a human-readable message out of an error body when present.
    private static func extractErrorMessage(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return envelope.error?.message ?? envelope.detail ?? envelope.message
        }
        return String(data: data, encoding: .utf8)?.prefix(200).description
    }
}

// MARK: - Wire DTOs (kept private to the client)

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let topP: Double
    let maxTokens: Int
    let stream: Bool

    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case topP = "top_p"
        case maxTokens = "max_tokens"
    }
}

private struct ChatResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable { let message: Message }
    struct Message: Decodable {
        let role: String?
        let content: String?
    }
}

private struct ModelsResponse: Decodable {
    let data: [NIMModel]
}

private struct ErrorEnvelope: Decodable {
    let error: ErrorBody?
    let detail: String?
    let message: String?
    struct ErrorBody: Decodable { let message: String? }
}
