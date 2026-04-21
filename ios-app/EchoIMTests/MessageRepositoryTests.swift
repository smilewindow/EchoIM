import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("MessageRepository")
struct MessageRepositoryTests {
    private let mkBody: (String) -> Data = { $0.data(using: .utf8)! }

    @Test func listInitialHitsEndpointAndDecodes() async throws {
        var capturedURL: URL?
        let body = mkBody("""
        [
          { "id": 10, "conversation_id": 5, "sender_id": 3,
            "body": "older", "message_type": "text", "media_url": null,
            "created_at": "2026-04-20T09:00:00.000Z" },
          { "id": 11, "conversation_id": 5, "sender_id": 9,
            "body": "newer", "message_type": "text", "media_url": null,
            "created_at": "2026-04-20T09:01:00.000Z" }
        ]
        """)
        let (config, _) = MockURLProtocol.configure { req in
            capturedURL = req.url
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let repo = MessageRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        let msgs = try await repo.list(conversationId: 5, cursor: nil, token: "jwt")

        #expect(capturedURL?.path == "/api/conversations/5/messages")
        #expect(capturedURL?.query == nil || capturedURL?.query?.isEmpty == true)
        #expect(msgs.count == 2)
        #expect(msgs[0].id == 10)
    }

    @Test func listBeforeBuildsQuerystring() async throws {
        var capturedURL: URL?
        let (config, _) = MockURLProtocol.configure { req in
            capturedURL = req.url
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                mkBody("[]")
            )
        }
        let repo = MessageRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        _ = try await repo.list(conversationId: 5, cursor: .before(100), token: "jwt")

        let comps = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)!
        #expect(comps.path == "/api/conversations/5/messages")
        let before = comps.queryItems?.first { $0.name == "before" }?.value
        #expect(before == "100")
    }

    @Test func listAfterBuildsQuerystring() async throws {
        var capturedURL: URL?
        let (config, _) = MockURLProtocol.configure { req in
            capturedURL = req.url
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                mkBody("[]")
            )
        }
        let repo = MessageRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        _ = try await repo.list(conversationId: 5, cursor: .after(200), token: "jwt")

        let comps = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)!
        let after = comps.queryItems?.first { $0.name == "after" }?.value
        #expect(after == "200")
    }

    @Test func sendTextPostsSnakeCaseBodyAndDecodesResponse() async throws {
        var capturedMethod: String?
        var capturedPath: String?
        var capturedBody: Data?
        let body = mkBody("""
        { "id": 500, "conversation_id": 5, "sender_id": 9,
          "body": "hi", "message_type": "text", "media_url": null,
          "created_at": "2026-04-20T10:00:00.000Z",
          "client_temp_id": "pending-1" }
        """)
        let (config, _) = MockURLProtocol.configure { req in
            capturedMethod = req.httpMethod
            capturedPath = req.url?.path
            if let stream = req.httpBodyStream { capturedBody = Data(reading: stream) }
            else { capturedBody = req.httpBody }
            return (
                HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let repo = MessageRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        let result = try await repo.sendText(
            recipientId: 3, body: "hi", clientTempId: "pending-1", token: "jwt"
        )

        #expect(capturedMethod == "POST")
        #expect(capturedPath == "/api/messages")
        let dict = try JSONSerialization.jsonObject(with: capturedBody ?? Data()) as? [String: Any]
        #expect(dict?["recipient_id"] as? Int == 3)
        #expect(dict?["body"] as? String == "hi")
        #expect(dict?["client_temp_id"] as? String == "pending-1")
        // 不显式传 message_type，服务端 default 处理
        #expect(dict?["message_type"] == nil)
        #expect(result.id == 500)
        #expect(result.clientTempId == "pending-1")
    }
}
