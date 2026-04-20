import Foundation
import Testing
@testable import EchoIM

@Suite("FriendRequest decoding")
struct FriendRequestDecodingTests {
    @Test
    func decodesIncomingPayload() throws {
        let json = """
        {
          "id": 10, "sender_id": 3, "recipient_id": 9, "status": "pending",
          "created_at": "2026-04-19T08:30:12.345Z",
          "updated_at": "2026-04-19T08:30:12.345Z",
          "username": "alice", "display_name": "Alice", "avatar_url": null
        }
        """.data(using: .utf8)!

        let request = try APIClient.jsonDecoder.decode(FriendRequest.self, from: json)

        #expect(request.id == 10)
        #expect(request.senderId == 3)
        #expect(request.recipientId == 9)
        #expect(request.status == .pending)
        #expect(request.username == "alice")
        #expect(request.direction == nil)
    }

    @Test
    func decodesHistoryWithDirection() throws {
        let json = """
        {
          "id": 11, "sender_id": 3, "recipient_id": 9, "status": "accepted",
          "created_at": "2026-04-19T08:30:12.345Z",
          "updated_at": "2026-04-19T08:31:00.000Z",
          "direction": "received",
          "username": "alice", "display_name": null, "avatar_url": null
        }
        """.data(using: .utf8)!

        let request = try APIClient.jsonDecoder.decode(FriendRequest.self, from: json)

        #expect(request.status == .accepted)
        #expect(request.direction == "received")
    }

    @Test
    func decodesBarePostResponseWithoutJoinedUser() throws {
        let json = """
        {
          "id": 12, "sender_id": 3, "recipient_id": 9, "status": "pending",
          "created_at": "2026-04-19T08:30:12.345Z",
          "updated_at": "2026-04-19T08:30:12.345Z"
        }
        """.data(using: .utf8)!

        let request = try APIClient.jsonDecoder.decode(FriendRequest.self, from: json)

        #expect(request.username == nil)
        #expect(request.displayName == nil)
    }
}
