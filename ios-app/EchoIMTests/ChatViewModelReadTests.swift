import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ChatViewModel — mark read")
struct ChatViewModelReadTests {
    final class FakeMessageRepo: MessageRepository {
        var listResult: Result<[Message], Error> = .success([])
        private(set) var markCalls: [(convId: Int, id: Int)] = []

        func list(
            conversationId: Int,
            cursor: MessageCursor?,
            limit: Int?,
            token: String
        ) async throws -> [Message] {
            try listResult.get()
        }

        func sendText(
            recipientId: Int,
            body: String,
            clientTempId: String,
            token: String
        ) async throws -> Message {
            throw APIError.invalidResponse
        }

        func sendImage(
            recipientId: Int,
            mediaUrl: String,
            clientTempId: String,
            token: String
        ) async throws -> Message {
            throw APIError.invalidResponse
        }

        func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {
            markCalls.append((conversationId, lastReadMessageId))
        }
    }

    private func makeConversation(
        id: Int = 5,
        peerId: Int = 9,
        lastReadMessageId: Int? = nil
    ) -> Conversation {
        let lastRead = lastReadMessageId.map(String.init) ?? "null"
        let json = """
        { "id": \(id), "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": \(peerId), "peer_username": "alice",
          "peer_display_name": null, "peer_avatar_url": null,
          "last_message_body": null, "last_message_type": null,
          "last_message_sender_id": null, "last_message_at": null,
          "last_read_message_id": \(lastRead), "unread_count": 0 }
        """.data(using: .utf8)!
        return try! APIClient.jsonDecoder.decode(Conversation.self, from: json)
    }

    private func msg(id: Int, senderId: Int = 3) -> Message {
        Message(
            id: id,
            conversationId: 5,
            senderId: senderId,
            body: "hi",
            messageType: "text",
            mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
            clientTempId: nil
        )
    }

    @Test
    func markReadSendsLatestConfirmedMessageId() async {
        let repo = FakeMessageRepo()
        repo.listResult = .success([msg(id: 3), msg(id: 2), msg(id: 1)])
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )

        await vm.load()
        await vm.markReadIfNeeded()

        #expect(repo.markCalls.count == 1)
        #expect(repo.markCalls[0].id == 3)
    }

    @Test
    func markReadIsNoOpOnEmptyMessages() async {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )

        await vm.markReadIfNeeded()

        #expect(repo.markCalls.isEmpty)
    }

    @Test
    func markReadSkipsWhenCursorAlreadyAdvanced() async {
        let repo = FakeMessageRepo()
        repo.listResult = .success([msg(id: 3), msg(id: 2), msg(id: 1)])
        let vm = ChatViewModel(
            route: .conversation(makeConversation(lastReadMessageId: 3)),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )

        await vm.load()
        await vm.markReadIfNeeded()

        #expect(repo.markCalls.isEmpty)
    }

    @Test
    func markReadSkipsForDraftConversation() async {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .peer(UserProfile(id: 9, username: "a", displayName: nil, avatarUrl: nil)),
            currentUserId: 3,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )

        await vm.markReadIfNeeded()

        #expect(repo.markCalls.isEmpty)
    }
}
