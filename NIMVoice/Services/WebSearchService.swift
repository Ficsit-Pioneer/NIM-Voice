import Foundation

/// Keyless web search used to ground the model's answers. Combines DuckDuckGo's
/// Instant Answer API and Wikipedia search — neither needs an API key.
///
/// Best-effort by design: every network call is wrapped in `try?` and the whole
/// thing returns `nil` when nothing useful is found, so a failed or empty search
/// never blocks the conversation — the model just answers from its own knowledge.
struct WebSearchService: Sendable {
    static let shared = WebSearchService()

    private let session: URLSession
    private let userAgent = "NIMVoice/1.0 (iOS voice assistant)"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns a formatted context block of results, or nil if nothing was found.
    func search(_ query: String) async -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }

        // Query both sources concurrently.
        async let ddg = duckDuckGo(trimmed)
        async let wiki = wikipedia(trimmed)
        let lines = (await ddg ?? []) + (await wiki ?? [])

        guard !lines.isEmpty else { return nil }
        let body = lines.prefix(6).joined(separator: "\n")
        return "Web search results for \"\(trimmed)\":\n\n\(body)"
    }

    // MARK: - DuckDuckGo Instant Answer

    private func duckDuckGo(_ query: String) async -> [String]? {
        guard var components = URLComponents(string: "https://api.duckduckgo.com/") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let answer = try? JSONDecoder().decode(DDGResponse.self, from: data) else {
            return nil
        }

        var lines: [String] = []
        if let direct = answer.Answer, !direct.isEmpty {
            lines.append("Answer: \(direct)")
        }
        if let abstract = answer.AbstractText, !abstract.isEmpty {
            let source = answer.AbstractURL.map { " (\($0))" } ?? ""
            lines.append("\(abstract)\(source)")
        }
        if let definition = answer.Definition, !definition.isEmpty {
            let source = answer.DefinitionURL.map { " (\($0))" } ?? ""
            lines.append("Definition: \(definition)\(source)")
        }
        for topic in flatten(answer.RelatedTopics ?? []).prefix(3) {
            if let text = topic.Text, !text.isEmpty { lines.append(text) }
        }
        return lines.isEmpty ? nil : lines
    }

    private func flatten(_ topics: [DDGTopic]) -> [DDGTopic] {
        topics.flatMap { topic -> [DDGTopic] in
            if let nested = topic.Topics { return flatten(nested) }
            return [topic]
        }
    }

    // MARK: - Wikipedia search

    private func wikipedia(_ query: String) async -> [String]? {
        guard var components = URLComponents(string: "https://en.wikipedia.org/w/api.php") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srlimit", value: "3"),
            URLQueryItem(name: "srprop", value: "snippet"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(WikiResponse.self, from: data) else {
            return nil
        }

        let lines = result.query.search.prefix(3).map { item in
            "Wikipedia — \(item.title): \(Self.stripHTML(item.snippet))"
        }
        return lines.isEmpty ? nil : Array(lines)
    }

    private static func stripHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Wire DTOs

private struct DDGResponse: Decodable {
    let Answer: String?
    let AbstractText: String?
    let AbstractURL: String?
    let Definition: String?
    let DefinitionURL: String?
    let RelatedTopics: [DDGTopic]?
}

private struct DDGTopic: Decodable {
    let Text: String?
    let FirstURL: String?
    let Topics: [DDGTopic]?
}

private struct WikiResponse: Decodable {
    let query: Query
    struct Query: Decodable { let search: [Item] }
    struct Item: Decodable {
        let title: String
        let snippet: String
    }
}
