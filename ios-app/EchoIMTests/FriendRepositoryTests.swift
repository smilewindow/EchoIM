import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("FriendRepository")
struct FriendRepositoryTests {
    @Test
    func listDecodesAndHitsEndpoint() async throws {
        var capturedPath: String?
        let body = """
        [
          { "id": 1, "username": "alice", "display_name": "Alice", "avatar_url": null },
          { "id": 2, "username": "bob", "display_name": null, "avatar_url": "/u/2.jpg" }
        ]
        """.data(using: .utf8)!
        let (configuration, _) = MockURLProtocol.configure { request in
            capturedPath = request.url?.path
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
        let client = APIClient(session: URLSession(configuration: configuration))
        let repo = FriendRepositoryImpl(api: client)

        let friends = try await repo.list(token: "jwt")

        #expect(capturedPath == "/api/friends")
        #expect(friends.count == 2)
        #expect(friends[0].id == 1)
        #expect(friends[0].displayName == "Alice")
        #expect(friends[1].avatarUrl == "/u/2.jpg")
    }
}
