import XCTest
@testable import NIMVoice

/// Exercises `NIMClient`'s real encode/decode/error paths against stubbed HTTP
/// responses — no network involved.
final class NIMClientTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.responder = nil
        super.tearDown()
    }

    private func makeClient() -> NIMClient {
        NIMClient(session: MockURLProtocol.makeSession())
    }

    private func ok(_ url: URL?, _ status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url ?? URL(string: "https://integrate.api.nvidia.com/v1")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    func testChatExtractsAndTrimsContent() async throws {
        MockURLProtocol.responder = { request in
            let body = #"{"choices":[{"index":0,"message":{"role":"assistant","content":"  Hello there.  "}}]}"#
            return (self.ok(request.url), Data(body.utf8))
        }
        let reply = try await makeClient().chat(
            messages: [ChatMessage(role: .user, content: "hi")],
            model: "nvidia/test",
            params: .default,
            apiKey: "test-key"
        )
        XCTAssertEqual(reply, "Hello there.")
    }

    func testChatSendsBearerToken() async throws {
        var seenAuth: String?
        MockURLProtocol.responder = { request in
            seenAuth = request.value(forHTTPHeaderField: "Authorization")
            let body = #"{"choices":[{"message":{"content":"ok"}}]}"#
            return (self.ok(request.url), Data(body.utf8))
        }
        _ = try await makeClient().chat(messages: [], model: "m", params: .default, apiKey: "abc123")
        XCTAssertEqual(seenAuth, "Bearer abc123")
    }

    func testListModelsParsesAndSortsAscending() async throws {
        MockURLProtocol.responder = { request in
            let body = #"{"object":"list","data":[{"id":"nvidia/zephyr"},{"id":"meta/llama-3.1"},{"id":"nvidia/nv-embedqa-e5-v5"}]}"#
            return (self.ok(request.url), Data(body.utf8))
        }
        let models = try await makeClient().listModels(apiKey: "test-key")
        XCTAssertEqual(models.map(\.id), ["meta/llama-3.1", "nvidia/nv-embedqa-e5-v5", "nvidia/zephyr"])
        XCTAssertEqual(models.first?.displayName, "llama-3.1")
        XCTAssertEqual(models.first?.vendor, "meta")
    }

    func testUnauthorizedStatusMapsToNIMError() async {
        MockURLProtocol.responder = { request in (self.ok(request.url, 401), Data("{}".utf8)) }
        do {
            _ = try await makeClient().listModels(apiKey: "bad")
            XCTFail("Expected an error to be thrown")
        } catch let error as NIMError {
            guard case .unauthorized = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Expected NIMError, got \(error)")
        }
    }

    func testEmptyContentThrowsEmptyResponse() async {
        MockURLProtocol.responder = { request in
            let body = #"{"choices":[{"message":{"role":"assistant","content":"   "}}]}"#
            return (self.ok(request.url), Data(body.utf8))
        }
        do {
            _ = try await makeClient().chat(messages: [], model: "m", params: .default, apiKey: "k")
            XCTFail("Expected an error to be thrown")
        } catch let error as NIMError {
            guard case .emptyResponse = error else {
                return XCTFail("Expected .emptyResponse, got \(error)")
            }
        } catch {
            XCTFail("Expected NIMError, got \(error)")
        }
    }

    func testMissingKeyThrowsBeforeNetwork() async {
        // No responder set: if we reached the network the stub would fail loudly.
        do {
            _ = try await makeClient().chat(messages: [], model: "m", params: .default, apiKey: "")
            XCTFail("Expected an error to be thrown")
        } catch let error as NIMError {
            guard case .missingAPIKey = error else {
                return XCTFail("Expected .missingAPIKey, got \(error)")
            }
        } catch {
            XCTFail("Expected NIMError, got \(error)")
        }
    }

    func testModelCategoryDerivation() {
        XCTAssertEqual(NIMModel(id: "nvidia/llama-3.3-nemotron-super-49b-v1").category, .chat)
        XCTAssertEqual(NIMModel(id: "nvidia/nv-embedqa-e5-v5").category, .embedding)
        XCTAssertEqual(NIMModel(id: "nvidia/llama-3.1-nemoguard-8b").category, .safety)
        XCTAssertEqual(NIMModel(id: "meta/llama-3.2-90b-vision-instruct").category, .vision)
        XCTAssertFalse(NIMModel(id: "nvidia/nv-embedqa-e5-v5").isChatCapable)
    }
}
