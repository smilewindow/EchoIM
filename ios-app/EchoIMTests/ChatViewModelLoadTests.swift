import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ChatViewModel — load / paginate")
struct ChatViewModelLoadTests {
    final class FakeMessageRepo: MessageRepository {
        var listResult: Result<[Message], Error> = .success([])
        private(set) var calls: [(Int, MessageCursor?)] = []

        func list(conversationId: Int, cursor: MessageCursor?, token: String) async throws -> [Message] {
            calls.append((conversationId, cursor))
            return try listResult.get()
        }

        func sendText(
            recipientId: Int,
            body: String,
            clientTempId: String,
            token: String
        ) async throws -> Message {
            throw APIError.invalidResponse
        }
    }

    private func makeMessage(id: Int, body: String) -> Message {
        Message(
            id: id,
            conversationId: 5,
            senderId: 3,
            body: body,
            messageType: "text",
            mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
            clientTempId: nil
        )
    }

    @Test
    func loadLatestReversesDescToAscendingChronological() async {
        let repo = FakeMessageRepo()
        // 服务端返回 DESC（最新在前）
        repo.listResult = .success([
            makeMessage(id: 3, body: "c"),
            makeMessage(id: 2, body: "b"),
            makeMessage(id: 1, body: "a"),
        ])
        let vm = ChatViewModel(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )

        await vm.load()

        #expect(vm.messages.count == 3)
        #expect(vm.messages[0].message.id == 1)
        #expect(vm.messages[2].message.id == 3)
        #expect(vm.phase == .loaded)
    }

    @Test
    func loadEmptyShowsEmptyPhase() async {
        let repo = FakeMessageRepo()
        repo.listResult = .success([])
        let vm = ChatViewModel(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )

        await vm.load()

        #expect(vm.messages.isEmpty)
        #expect(vm.phase == .loaded)
    }

    @Test
    func loadErrorSetsErrorPhase() async {
        let repo = FakeMessageRepo()
        repo.listResult = .failure(APIError.invalidResponse)
        let vm = ChatViewModel(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )

        await vm.load()

        if case .error = vm.phase { return }
        Issue.record("expected .error")
    }

    @Test
    func loadOlderAppendsToTopWithBeforeCursor() async {
        let repo = FakeMessageRepo()
        repo.listResult = .success(
            (28...77).reversed().map { makeMessage(id: $0, body: "m-\($0)") }
        )
        let vm = ChatViewModel(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )

        await vm.load()
        #expect(vm.messages.first?.message.id == 28)

        repo.listResult = .success([
            makeMessage(id: 27, body: "older2"),
            makeMessage(id: 26, body: "older1"),
        ])
        await vm.loadOlder()

        #expect(vm.messages.count == 52)
        #expect(vm.messages[0].message.id == 26)
        #expect(vm.messages[1].message.id == 27)
        #expect(vm.messages[2].message.id == 28)
        guard repo.calls.count > 1 else {
            Issue.record("expected loadOlder to call repo")
            return
        }
        #expect(repo.calls[1].1 == .before(28))
    }

    @Test
    func draftRouteSkipsNetwork() async {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .peer(UserProfile(id: 9, username: "alice", displayName: nil, avatarUrl: nil)),
            currentUserId: 3,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )

        await vm.load()

        #expect(repo.calls.isEmpty)
        #expect(vm.messages.isEmpty)
        #expect(vm.phase == .loaded)
    }

    private func makeConversation(id: Int, peerId: Int) -> Conversation {
        // 用服务端同形 JSON 造 fixture，顺便覆盖 peer_* → UserProfile 的解码路径。
        let json = """
        {
          "id": \(id),
          "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": \(peerId), "peer_username": "alice",
          "peer_display_name": null, "peer_avatar_url": null,
          "last_message_body": null, "last_message_type": null,
          "last_message_sender_id": null, "last_message_at": null,
          "last_read_message_id": null, "unread_count": 0
        }
        """.data(using: .utf8)!
        return try! APIClient.jsonDecoder.decode(Conversation.self, from: json)
    }
}
