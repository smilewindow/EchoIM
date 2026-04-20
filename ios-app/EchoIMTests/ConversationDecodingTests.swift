import Foundation
import Testing
@testable import EchoIM

@Suite("Conversation decoding")
struct ConversationDecodingTests {
    @Test
    func aggregatesFlatPeerFieldsIntoUserProfile() throws {
        let json = """
        {
          "id": 5,
          "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": 9,
          "peer_username": "alice",
          "peer_display_name": "Alice A.",
          "peer_avatar_url": "/uploads/avatars/9.jpg",
          "last_message_body": "hi",
          "last_message_type": "text",
          "last_message_sender_id": 9,
          "last_message_at": "2026-04-18T13:00:00.000Z",
          "last_read_message_id": 123,
          "unread_count": 2
        }
        """.data(using: .utf8)!

        let conversation = try APIClient.jsonDecoder.decode(Conversation.self, from: json)

        #expect(conversation.id == 5)
        #expect(conversation.peer.id == 9)
        #expect(conversation.peer.username == "alice")
        #expect(conversation.peer.displayName == "Alice A.")
        #expect(conversation.peer.avatarUrl == "/uploads/avatars/9.jpg")
        #expect(conversation.lastMessageBody == "hi")
        #expect(conversation.lastMessageType == "text")
        #expect(conversation.lastMessageSenderId == 9)
        #expect(conversation.unreadCount == 2)
        #expect(conversation.lastReadMessageId == 123)
    }

    @Test
    func acceptsMinimalConversationWithoutLastMessage() throws {
        let json = """
        {
          "id": 6,
          "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": 10,
          "peer_username": "bob",
          "peer_display_name": null,
          "peer_avatar_url": null,
          "last_message_body": null,
          "last_message_type": null,
          "last_message_sender_id": null,
          "last_message_at": null,
          "last_read_message_id": null,
          "unread_count": 0
        }
        """.data(using: .utf8)!

        let conversation = try APIClient.jsonDecoder.decode(Conversation.self, from: json)

        #expect(conversation.lastMessageAt == nil)
        #expect(conversation.unreadCount == 0)
        #expect(conversation.peer.displayName == nil)
    }
}
