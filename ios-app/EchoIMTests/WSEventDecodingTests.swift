import Testing
import Foundation
@testable import EchoIM

@Suite("WSEvent decoding")
struct WSEventDecodingTests {
    private func decode(_ json: String) throws -> WSEvent {
        try APIClient.jsonDecoder.decode(WSEvent.self, from: json.data(using: .utf8)!)
    }

    @Test func decodesMessageNew() throws {
        let ev = try decode("""
        { "type": "message.new", "payload": {
            "id": 200, "conversation_id": 7, "sender_id": 3,
            "body": "hey", "message_type": "text", "media_url": null,
            "created_at": "2026-04-20T09:00:00.000Z"
          } }
        """)
        guard case .messageNew(let msg) = ev else {
            Issue.record("expected .messageNew")
            return
        }
        #expect(msg.id == 200)
        #expect(msg.body == "hey")
    }

    @Test func decodesMessageNewWithClientTempId() throws {
        let ev = try decode("""
        { "type": "message.new", "payload": {
            "id": 201, "conversation_id": 7, "sender_id": 9,
            "body": "echo", "message_type": "text", "media_url": null,
            "created_at": "2026-04-20T09:00:10.000Z",
            "client_temp_id": "pending-abc"
          } }
        """)
        guard case .messageNew(let msg) = ev else {
            Issue.record("expected .messageNew")
            return
        }
        #expect(msg.clientTempId == "pending-abc")
    }

    @Test func decodesConversationUpdated() throws {
        let ev = try decode("""
        { "type": "conversation.updated",
          "payload": { "conversation_id": 7, "last_read_message_id": 199 } }
        """)
        guard case .conversationUpdated(let p) = ev else {
            Issue.record("expected .conversationUpdated")
            return
        }
        #expect(p.conversationId == 7)
        #expect(p.lastReadMessageId == 199)
    }

    @Test func decodesTypingStart() throws {
        let ev = try decode("""
        { "type": "typing.start",
          "payload": { "conversation_id": 7, "user_id": 3 } }
        """)
        if case .typingStart(let p) = ev {
            #expect(p.conversationId == 7)
            #expect(p.userId == 3)
        } else {
            Issue.record("expected .typingStart")
        }
    }

    @Test func decodesTypingStop() throws {
        let ev = try decode("""
        { "type": "typing.stop",
          "payload": { "conversation_id": 7, "user_id": 3 } }
        """)
        if case .typingStop = ev { return }
        Issue.record("expected .typingStop")
    }

    @Test func decodesPresenceOnline() throws {
        let ev = try decode("""
        { "type": "presence.online", "payload": { "user_id": 3 } }
        """)
        if case .presenceOnline(let p) = ev {
            #expect(p.userId == 3)
        } else {
            Issue.record("expected .presenceOnline")
        }
    }

    @Test func decodesPresenceOffline() throws {
        let ev = try decode("""
        { "type": "presence.offline", "payload": { "user_id": 3 } }
        """)
        if case .presenceOffline = ev { return }
        Issue.record("expected .presenceOffline")
    }

    @Test func decodesFriendRequestNewAcceptedDeclined() throws {
        let fr = """
        { "id": 10, "sender_id": 1, "recipient_id": 2, "status": "pending",
          "created_at": "2026-04-20T09:00:00.000Z",
          "updated_at": "2026-04-20T09:00:00.000Z",
          "username": "alice", "display_name": null, "avatar_url": null }
        """
        let new = try decode(#"{ "type": "friend_request.new", "payload": \#(fr) }"#)
        if case .friendRequestNew = new { } else { Issue.record("expected .friendRequestNew") }

        let accepted = try decode(#"{ "type": "friend_request.accepted", "payload": \#(fr) }"#)
        if case .friendRequestAccepted = accepted { } else { Issue.record("expected .friendRequestAccepted") }

        let declined = try decode(#"{ "type": "friend_request.declined", "payload": \#(fr) }"#)
        if case .friendRequestDeclined = declined { } else { Issue.record("expected .friendRequestDeclined") }
    }

    @Test func unknownTypeDecodesToUnknown() throws {
        let ev = try decode("""
        { "type": "server.experimental", "payload": { "foo": 1 } }
        """)
        if case .unknown(let type) = ev {
            #expect(type == "server.experimental")
        } else {
            Issue.record("expected .unknown")
        }
    }
}
