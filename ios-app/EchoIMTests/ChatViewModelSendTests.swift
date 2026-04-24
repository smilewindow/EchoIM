import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ChatViewModel — send / retry")
struct ChatViewModelSendTests {
    final class FakeMessageRepo: MessageRepository {
        var listResult: Result<[Message], Error> = .success([])
        var sendResult: Result<Message, Error> = .failure(APIError.invalidResponse)
        var sendDelay: TimeInterval = 0
        private(set) var sendCalls: [(recipientId: Int, body: String, tempId: String)] = []

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
            sendCalls.append((recipientId, body, clientTempId))
            if sendDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(sendDelay * 1_000_000_000))
            }
            return try sendResult.get()
        }

        func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
    }

    private let peer = UserProfile(id: 9, username: "alice", displayName: nil, avatarUrl: nil)

    private func makeVM(
        route: ChatRoute,
        currentUserId: Int,
        repo: FakeMessageRepo
    ) -> ChatViewModel {
        ChatViewModel(
            route: route,
            currentUserId: currentUserId,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )
    }

    private func srvMessage(
        id: Int,
        convId: Int = 5,
        senderId: Int = 3,
        body: String = "hi",
        tempId: String? = nil
    ) -> Message {
        Message(
            id: id,
            conversationId: convId,
            senderId: senderId,
            body: body,
            messageType: "text",
            mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
            clientTempId: tempId
        )
    }

    @Test
    func sendOptimisticallyAppendsPendingBubble() async {
        let repo = FakeMessageRepo()
        repo.sendDelay = 0.05
        repo.sendResult = .success(srvMessage(id: 500, senderId: 3, body: "hi", tempId: "pending-X"))
        let vm = makeVM(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 3,
            repo: repo
        )

        let task = Task { await vm.sendText("hi") }

        // 等 VM 把 optimistic bubble 入队。
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].sendState == .pending)
        #expect(vm.messages[0].message.body == "hi")

        await task.value

        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].sendState == .confirmed)
        #expect(vm.messages[0].message.id == 500)
    }

    @Test
    func sendInDraftConversationBackfillsConversationId() async {
        let repo = FakeMessageRepo()
        repo.sendResult = .success(
            srvMessage(id: 700, convId: 42, senderId: 3, body: "hi", tempId: "pending-X")
        )
        let vm = makeVM(route: .peer(peer), currentUserId: 3, repo: repo)
        #expect(vm.conversationId == nil)

        await vm.sendText("hi")

        #expect(vm.conversationId == 42)
        #expect(vm.messages[0].message.id == 700)
    }

    @Test
    func sendFailureMarksBubbleFailed() async {
        let repo = FakeMessageRepo()
        repo.sendResult = .failure(APIError.invalidResponse)
        let vm = makeVM(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 3,
            repo: repo
        )

        await vm.sendText("hi")

        #expect(vm.messages.count == 1)
        if case .failed = vm.messages[0].sendState { } else {
            Issue.record("expected .failed")
        }
    }

    @Test
    func retryFailedMessageResendsWithSameTempId() async {
        let repo = FakeMessageRepo()
        repo.sendResult = .failure(APIError.invalidResponse)
        let vm = makeVM(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 3,
            repo: repo
        )
        await vm.sendText("hi")
        #expect(vm.messages[0].sendState != .confirmed)
        let firstTempId = vm.messages[0].localId

        repo.sendResult = .success(srvMessage(id: 888, body: "hi", tempId: firstTempId))
        await vm.retry(localId: firstTempId)

        #expect(vm.messages[0].sendState == .confirmed)
        #expect(vm.messages[0].message.id == 888)
        #expect(repo.sendCalls.count == 2)
        #expect(repo.sendCalls[0].tempId == repo.sendCalls[1].tempId)
    }

    @Test
    func retryOnConfirmedIsNoOp() async {
        let repo = FakeMessageRepo()
        repo.sendResult = .success(srvMessage(id: 1, body: "hi", tempId: "pending-X"))
        let vm = makeVM(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 3,
            repo: repo
        )
        await vm.sendText("hi")
        let localId = vm.messages[0].localId

        await vm.retry(localId: localId)

        #expect(repo.sendCalls.count == 1)
    }

    private func makeConversation(id: Int, peerId: Int) -> Conversation {
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
