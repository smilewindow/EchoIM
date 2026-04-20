import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("ConversationRepository")
struct ConversationRepositoryTests {
    @Test
    func listHitsEndpointAndDecodes() async throws {
        var capturedPath: String?
        var capturedAuthorization: String?
        let body = """
        [
          {
            "id": 5,
            "created_at": "2026-04-18T12:00:00.000Z",
            "peer_id": 9,
            "peer_username": "alice",
            "peer_display_name": "Alice",
            "peer_avatar_url": null,
            "last_message_body": "hi",
            "last_message_type": "text",
            "last_message_sender_id": 9,
            "last_message_at": "2026-04-18T13:00:00.000Z",
            "last_read_message_id": 100,
            "unread_count": 1
          }
        ]
        """.data(using: .utf8)!
        let (configuration, _) = MockURLProtocol.configure { request in
            capturedPath = request.url?.path
            capturedAuthorization = request.value(forHTTPHeaderField: "Authorization")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                body
            )
        }
        let repo = ConversationRepositoryImpl(
            api: APIClient(session: URLSession(configuration: configuration))
        )

        let list = try await repo.list(token: "jwt")

        #expect(capturedPath == "/api/conversations")
        #expect(capturedAuthorization == "Bearer jwt")
        #expect(list.count == 1)
        #expect(list[0].peer.username == "alice")
        #expect(list[0].unreadCount == 1)
    }
}
