import Foundation

/// Keyless web search + page reading used to ground the model's answers.
/// Combines DuckDuckGo's Instant Answer API and Wikipedia search (no API key),
/// then *reads the actual top result pages* so the model sees real page content
/// rather than just snippets.
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

    private struct SourceResult: Sendable {
        let lines: [String]
        let urls: [String]
    }

    /// Returns a formatted context block (snippets + read page text), or nil.
    /// `location`, when set (e.g. "Austin, Texas, United States"), is added to the
    /// query and the context so "nearby" questions have a reference point.
    func search(_ query: String, location: String? = nil) async -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }

        // Bias the lookups toward the user's area when we have a location.
        let effectiveQuery = location.map { "\(trimmed) \($0)" } ?? trimmed

        async let ddg = duckDuckGo(effectiveQuery)
        async let wiki = wikipedia(effectiveQuery)
        let ddgResult = await ddg
        let wikiResult = await wiki

        let snippetLines = (ddgResult?.lines ?? []) + (wikiResult?.lines ?? [])
        let candidateURLs = uniqued((ddgResult?.urls ?? []) + (wikiResult?.urls ?? []))

        // Read the top pages concurrently so the model sees real content.
        let pageSections = await readPages(Array(candidateURLs.prefix(2)))

        guard !snippetLines.isEmpty || !pageSections.isEmpty else { return nil }

        var blocks: [String] = []
        if let location { blocks.append("User's current location: \(location)") }
        if !snippetLines.isEmpty { blocks.append(snippetLines.prefix(6).joined(separator: "\n")) }
        blocks.append(contentsOf: pageSections)

        return "Web results for \"\(trimmed)\":\n\n" + blocks.joined(separator: "\n\n")
    }

    // MARK: - Page reading

    private func readPages(_ urls: [String]) async -> [String] {
        await withTaskGroup(of: String?.self) { group in
            for url in urls {
                group.addTask {
                    guard let text = await WebPageReader.shared.readText(from: url) else { return nil }
                    return "Page content from \(url):\n\(text)"
                }
            }
            var sections: [String] = []
            for await section in group {
                if let section { sections.append(section) }
            }
            return sections
        }
    }

    private func uniqued(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    // MARK: - DuckDuckGo Instant Answer

    private func duckDuckGo(_ query: String) async -> SourceResult? {
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
        var urls: [String] = []

        if let direct = answer.Answer, !direct.isEmpty {
            lines.append("Answer: \(direct)")
        }
        if let abstract = answer.AbstractText, !abstract.isEmpty {
            let source = answer.AbstractURL.map { " (\($0))" } ?? ""
            lines.append("\(abstract)\(source)")
        }
        if let absURL = answer.AbstractURL, !absURL.isEmpty { urls.append(absURL) }
        if let definition = answer.Definition, !definition.isEmpty {
            lines.append("Definition: \(definition)")
        }
        for topic in flatten(answer.RelatedTopics ?? []).prefix(4) {
            if let text = topic.Text, !text.isEmpty { lines.append(text) }
            if let link = topic.FirstURL, !link.isEmpty { urls.append(link) }
        }
        return (lines.isEmpty && urls.isEmpty) ? nil : SourceResult(lines: lines, urls: urls)
    }

    private func flatten(_ topics: [DDGTopic]) -> [DDGTopic] {
        topics.flatMap { topic -> [DDGTopic] in
            if let nested = topic.Topics { return flatten(nested) }
            return [topic]
        }
    }

    // MARK: - Wikipedia search

    private func wikipedia(_ query: String) async -> SourceResult? {
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

        var lines: [String] = []
        var urls: [String] = []
        for item in result.query.search.prefix(3) {
            lines.append("Wikipedia — \(item.title): \(Self.stripHTML(item.snippet))")
            if let encoded = item.title
                .replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                urls.append("https://en.wikipedia.org/wiki/\(encoded)")
            }
        }
        return lines.isEmpty ? nil : SourceResult(lines: lines, urls: urls)
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
