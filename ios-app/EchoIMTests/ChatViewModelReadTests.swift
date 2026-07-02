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
            mediaWidth: Int,
            mediaHeight: Int,
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

    final class SuspendableMarkReadRepo: MessageRepository {
        var listResult: Result<[Message], Error> = .success([])
        private(set) var markCalls: [(convId: Int, id: Int)] = []
        private var continuations: [CheckedContinuation<Void, Never>] = []

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
            mediaWidth: Int,
            mediaHeight: Int,
            clientTempId: String,
            token: String
        ) async throws -> Message {
            throw APIError.invalidResponse
        }

        func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {
            markCalls.append((conversationId, lastReadMessageId))
            await withCheckedContinuation { continuations.append($0) }
        }

        func resumeAll() {
            let waiting = continuations
            continuations = []
            waiting.forEach { $0.resume() }
        }
    }

    /// 有界轮询，避免断言失败时测试挂死。
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<1000 where !condition() {
            await Task.yield()
        }
    }

    // 注意：这两个用例不能走 vm.load()——load() 末尾会 await markReadIfNeeded()，
    // 配合会挂起的 markRead stub 将永远不返回（测试死锁）。改由 handleWSEvent 驱动。

    @Test
    func markReadCoalescesConcurrentCallsIntoOnePut() async {
        let repo = SuspendableMarkReadRepo()
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )

        // 对方消息触发内部 mark-read 任务，PUT 挂在 stub 里
        vm.handleWSEvent(.messageNew(msg(id: 3)))
        await waitUntil { !repo.markCalls.isEmpty }

        // PUT 在途期间的显式调用应命中 in-flight guard 直接返回，不新增 PUT
        await vm.markReadIfNeeded()
        await vm.markReadIfNeeded()
        #expect(repo.markCalls.count == 1)

        repo.resumeAll()
        await waitUntil { vm.lastReadMessageId == 3 }

        #expect(repo.markCalls.count == 1)
        #expect(repo.markCalls[0].id == 3)
    }

    @Test
    func markReadCatchesUpWhenNewerMessageArrivesDuringPut() async {
        let repo = SuspendableMarkReadRepo()
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )

        vm.handleWSEvent(.messageNew(msg(id: 3)))
        await waitUntil { !repo.markCalls.isEmpty }

        // 首个 PUT 在途期间又收到对方新消息（它的内部 mark-read 调用被 guard 挡下）
        vm.handleWSEvent(.messageNew(msg(id: 4)))
        repo.resumeAll()

        // 循环应以新游标补发第二个 PUT
        await waitUntil { repo.markCalls.count == 2 }
        repo.resumeAll()
        await waitUntil { vm.lastReadMessageId == 4 }

        #expect(repo.markCalls.count == 2)
        #expect(repo.markCalls[0].id == 3)
        #expect(repo.markCalls[1].id == 4)
    }

    @Test
    func markReadDeferredWhileAwayFromBottomAndFlushedOnReturn() async {
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

        // 用户上翻历史时收到新消息：不推进已读（对齐 Web 端语义）
        vm.updateIsNearBottom(false)
        vm.handleWSEvent(.messageNew(msg(id: 3)))
        for _ in 0..<20 { await Task.yield() }
        #expect(repo.markCalls.isEmpty)
        #expect(vm.lastReadMessageId == nil)

        // 滚回底部后补报
        vm.updateIsNearBottom(true)
        await waitUntil { vm.lastReadMessageId == 3 }
        #expect(repo.markCalls.count == 1)
        #expect(repo.markCalls[0].id == 3)
    }

    @Test
    func reconnectCatchUpAdvancesReadCursorWhenNearBottom() async {
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

        vm.handleWSEvent(.messageNew(msg(id: 3)))
        await waitUntil { vm.lastReadMessageId == 3 }

        // 重连补拉到 3 条新消息，用户在底部 → 立即推进已读游标
        repo.listResult = .success([msg(id: 4), msg(id: 5), msg(id: 6)])
        await vm.reconcileAfterReconnect(conversations: [])

        #expect(vm.messages.count == 4)
        #expect(repo.markCalls.last?.id == 6)
        #expect(vm.lastReadMessageId == 6)
    }

    @Test
    func reconnectCatchUpDefersReadCursorWhileAwayFromBottom() async {
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

        vm.handleWSEvent(.messageNew(msg(id: 3)))
        await waitUntil { vm.lastReadMessageId == 3 }

        // 用户翻在历史位置时断线重连补拉：先不推进已读（列表未读数保持）
        vm.updateIsNearBottom(false)
        repo.listResult = .success([msg(id: 4), msg(id: 5), msg(id: 6)])
        await vm.reconcileAfterReconnect(conversations: [])

        #expect(vm.messages.count == 4)
        #expect(vm.lastReadMessageId == 3)
        #expect(repo.markCalls.last?.id == 3)

        // 点角标/滚回底部 → 补报到最新
        vm.updateIsNearBottom(true)
        await waitUntil { vm.lastReadMessageId == 6 }
        #expect(repo.markCalls.last?.id == 6)
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
