import Testing
import Foundation
@testable import EchoIM

@Suite("Message decoding")
struct MessageDecodingTests {
    @Test func decodesTextMessageWithClientTempId() throws {
        let json = """
        {
          "id": 101, "conversation_id": 5, "sender_id": 9,
          "body": "hi", "message_type": "text", "media_url": null,
          "created_at": "2026-04-20T10:00:00.123Z",
          "client_temp_id": "pending-1234-1"
        }
        """.data(using: .utf8)!
        let m = try APIClient.jsonDecoder.decode(Message.self, from: json)
        #expect(m.id == 101)
        #expect(m.conversationId == 5)
        #expect(m.senderId == 9)
        #expect(m.body == "hi")
        #expect(m.messageType == "text")
        #expect(m.clientTempId == "pending-1234-1")
    }

    @Test func decodesMessageWithoutClientTempId() throws {
        let json = """
        {
          "id": 102, "conversation_id": 5, "sender_id": 3,
          "body": "yo", "message_type": "text", "media_url": null,
          "created_at": "2026-04-20T10:01:00.000Z"
        }
        """.data(using: .utf8)!
        let m = try APIClient.jsonDecoder.decode(Message.self, from: json)
        #expect(m.clientTempId == nil)
    }

    @Test func decodesImageMessage() throws {
        let json = """
        {
          "id": 103, "conversation_id": 5, "sender_id": 9,
          "body": null, "message_type": "image",
          "media_url": "/uploads/messages/9-1712345678.jpg",
          "created_at": "2026-04-20T10:02:00.000Z"
        }
        """.data(using: .utf8)!
        let m = try APIClient.jsonDecoder.decode(Message.self, from: json)
        #expect(m.body == nil)
        #expect(m.messageType == "image")
        #expect(m.mediaUrl == "/uploads/messages/9-1712345678.jpg")
    }
}
