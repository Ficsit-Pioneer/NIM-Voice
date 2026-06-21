import Foundation

/// Fetches a web page and extracts its readable text so the model can "see" the
/// actual content of a site (not just a search snippet).
///
/// Limitations to be honest about: this reads the raw HTML the server returns.
/// JavaScript-rendered pages (single-page apps, most live menu/price/ordering
/// sites) put their data in scripts, not HTML, so little useful text comes back.
/// Static, content-first pages (Wikipedia, articles, docs) read very well.
struct WebPageReader: Sendable {
    static let shared = WebPageReader()

    private let session: URLSession
    // A browser-like UA; some sites refuse non-browser clients.
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches `urlString` and returns extracted text (truncated), or nil.
    func readText(from urlString: String, maxCharacters: Int = 2200) async -> String? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 7

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        // Only parse HTML/text responses.
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard contentType.isEmpty || contentType.contains("html") || contentType.contains("text") else {
            return nil
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        let text = Self.extractText(from: html)
        guard text.count >= 80 else { return nil }   // too little to be useful
        return String(text.prefix(maxCharacters))
    }

    /// Crude, dependency-free HTML → text extraction. Good enough to give the
    /// model the gist of a content page.
    static func extractText(from html: String) -> String {
        var s = html

        // Drop non-content blocks entirely (including their contents).
        for tag in ["script", "style", "head", "noscript", "svg", "header", "footer", "nav"] {
            s = s.replacingOccurrences(
                of: "(?is)<\(tag)[^>]*>.*?</\(tag)>",
                with: " ",
                options: .regularExpression
            )
        }

        // Turn block-ending tags into line breaks so text doesn't run together.
        s = s.replacingOccurrences(
            of: "(?i)<(br|/p|/div|/li|/h[1-6]|/tr|/table)[^>]*>",
            with: "\n",
            options: .regularExpression
        )

        // Strip all remaining tags.
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        s = decodeEntities(s)

        // Collapse whitespace.
        s = s.replacingOccurrences(of: "[ \\t\\r\\f]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n[ ]*", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ string: String) -> String {
        var r = string
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                     "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&#160;": " ",
                     "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"]
        for (key, value) in named {
            r = r.replacingOccurrences(of: key, with: value)
        }
        // Drop any remaining numeric entities rather than mis-decoding them.
        r = r.replacingOccurrences(of: "&#\\d+;", with: "", options: .regularExpression)
        return r
    }
}
