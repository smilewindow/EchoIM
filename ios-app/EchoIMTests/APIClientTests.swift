import Testing
import Foundation
@testable import EchoIM

@Suite("APIClient JSON decoding")
struct APIClientTests {
    @Test
    @MainActor
    func decodesMessageWithFractionalSeconds() throws {
        let json = """
        {
          "id": 42,
          "conversation_id": 7,
          "sender_id": 3,
          "body": "hi",
          "message_type": "text",
          "media_url": null,
          "created_at": "2026-04-19T08:30:12.345Z",
          "client_temp_id": null
        }
        """.data(using: .utf8)!

        let decoder = APIClient.jsonDecoder
        let message = try decoder.decode(Message.self, from: json)
        #expect(message.id == 42)
        #expect(message.conversationId == 7)
        #expect(message.senderId == 3)
        #expect(message.body == "hi")
        #expect(message.messageType == "text")
        #expect(message.mediaUrl == nil)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(message.createdAt == formatter.date(from: "2026-04-19T08:30:12.345Z"))
    }

    @Test
    @MainActor
    func throwsUnauthorizedOn401() async throws {
        let url = URL(string: "http://test.local/fail")!
        let (configuration, _) = MockURLProtocol.configure { _ in
            (
                HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        let client = APIClient(session: URLSession(configuration: configuration))

        do {
            let _: EmptyResponse = try await client.request("x")
            Issue.record("expected .unauthorized")
        } catch let error as APIError {
            #expect(error == .unauthorized)
        }
    }
}
