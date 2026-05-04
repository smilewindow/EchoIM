import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ChatViewModel — timestamp + consecutive")
struct ChatViewModelTimestampTests {

    private let peer = UserProfile(id: 9, username: "alice", displayName: nil, avatarUrl: nil)

    private func makeMessage(id: Int, senderId: Int, createdAt: Date) -> Message {
        Message(
            id: id,
            conversationId: 1,
            senderId: senderId,
            body: "hi",
            messageType: "text",
            mediaUrl: nil,
            createdAt: createdAt,
            clientTempId: nil
        )
    }

    // MARK: - isConsecutive

    @Test
    func consecutiveWhenSameSenderWithin60Seconds() {
        let now = Date()
        let vm = ChatViewModel(
            route: .peer(peer), currentUserId: 1, messageRepo: FakeMessageRepo(),
            wsClient: nil, tokenProvider: { "tok" }
        )
        let msg1 = LocalMessage.confirmed(makeMessage(id: 1, senderId: 1, createdAt: now))
        let msg2 = LocalMessage.confirmed(makeMessage(id: 2, senderId: 1, createdAt: now.addingTimeInterval(59)))
        #expect(vm.isConsecutive(msg2, previous: msg1) == true)
    }

    @Test
    func notConsecutiveWhenDifferentSender() {
        let now = Date()
        let vm = ChatViewModel(
            route: .peer(peer), currentUserId: 1, messageRepo: FakeMessageRepo(),
            wsClient: nil, tokenProvider: { "tok" }
        )
        let msg1 = LocalMessage.confirmed(makeMessage(id: 1, senderId: 1, createdAt: now))
        let msg2 = LocalMessage.confirmed(makeMessage(id: 2, senderId: 2, createdAt: now.addingTimeInterval(10)))
        #expect(vm.isConsecutive(msg2, previous: msg1) == false)
    }

    @Test
    func notConsecutiveWhenOver60Seconds() {
        let now = Date()
        let vm = ChatViewModel(
            route: .peer(peer), currentUserId: 1, messageRepo: FakeMessageRepo(),
            wsClient: nil, tokenProvider: { "tok" }
        )
        let msg1 = LocalMessage.confirmed(makeMessage(id: 1, senderId: 1, createdAt: now))
        let msg2 = LocalMessage.confirmed(makeMessage(id: 2, senderId: 1, createdAt: now.addingTimeInterval(61)))
        #expect(vm.isConsecutive(msg2, previous: msg1) == false)
    }

    @Test
    func notConsecutiveWhenPreviousIsNil() {
        let vm = ChatViewModel(
            route: .peer(peer), currentUserId: 1, messageRepo: FakeMessageRepo(),
            wsClient: nil, tokenProvider: { "tok" }
        )
        let msg = LocalMessage.confirmed(makeMessage(id: 1, senderId: 1, createdAt: Date()))
        #expect(vm.isConsecutive(msg, previous: nil) == false)
    }

    // MARK: - shouldShowTimestamp

    @Test
    func firstMessageAlwaysShowsTimestamp() async throws {
        let now = Date()
        let vm = ChatViewModel(
            route: .conversation(try makeConversation()), currentUserId: 1,
            messageRepo: FakeMessageRepo(listResult: [makeMessage(id: 1, senderId: 1, createdAt: now)]),
            wsClient: nil, tokenProvider: { "tok" }
        )
        await vm.load()
        #expect(vm.shouldShowTimestamp(at: 0) == true)
    }

    @Test
    func showsTimestampWhenGapExceeds5Minutes() async throws {
        let now = Date()
        // FakeMessageRepo simulates server order: newest first
        let msgs = [
            makeMessage(id: 2, senderId: 1, createdAt: now.addingTimeInterval(301)),
            makeMessage(id: 1, senderId: 1, createdAt: now),
        ]
        let vm = ChatViewModel(
            route: .conversation(try makeConversation()), currentUserId: 1,
            messageRepo: FakeMessageRepo(listResult: msgs),
            wsClient: nil, tokenProvider: { "tok" }
        )
        await vm.load()
        #expect(vm.shouldShowTimestamp(at: 1) == true)
    }

    @Test
    func hidesTimestampWhenGapUnder5Minutes() async throws {
        let now = Date()
        // FakeMessageRepo simulates server order: newest first
        let msgs = [
            makeMessage(id: 2, senderId: 1, createdAt: now.addingTimeInterval(299)),
            makeMessage(id: 1, senderId: 1, createdAt: now),
        ]
        let vm = ChatViewModel(
            route: .conversation(try makeConversation()), currentUserId: 1,
            messageRepo: FakeMessageRepo(listResult: msgs),
            wsClient: nil, tokenProvider: { "tok" }
        )
        await vm.load()
        #expect(vm.shouldShowTimestamp(at: 1) == false)
    }

    // MARK: - Helpers

    private func makeConversation() throws -> Conversation {
        let json = """
        {
          "id": 1,
          "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": 9,
          "peer_username": "alice",
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
        return try APIClient.jsonDecoder.decode(Conversation.self, from: json)
    }

    private final class FakeMessageRepo: MessageRepository {
        var listResult: [Message]
        init(listResult: [Message] = []) { self.listResult = listResult }

        func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] {
            listResult
        }
        func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
            throw APIError.invalidResponse
        }
        func sendImage(recipientId: Int, mediaUrl: String, mediaWidth: Int, mediaHeight: Int, clientTempId: String, token: String) async throws -> Message {
            throw APIError.invalidResponse
        }
        func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
    }
}
