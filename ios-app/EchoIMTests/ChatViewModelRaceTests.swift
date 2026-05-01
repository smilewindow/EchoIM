import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ChatViewModel — race conditions")
struct ChatViewModelRaceTests {

    // MARK: - Blocking repo
    //
    // `actor` 保证内部状态串行访问；list() 在首次被调用后挂起自己，
    // 通过 waitUntilStarted() / releaseAll() 让测试精确控制挂起时序。

    actor BlockingRepo: MessageRepository {
        private let rows: [Message]
        private(set) var listCallCount = 0
        private(set) var sendCallCount = 0
        private var pendingContinuations: [CheckedContinuation<[Message], Error>] = []
        private var startedWaiters: [CheckedContinuation<Void, Never>] = []
        private var pendingSendContinuations: [CheckedContinuation<Message, Error>] = []
        private var sendStartedWaiters: [CheckedContinuation<Void, Never>] = []
        private(set) var lastSendTempId: String?

        init(rows: [Message] = []) {
            self.rows = rows
        }

        func list(
            conversationId: Int,
            cursor: MessageCursor?,
            limit: Int?,
            token: String
        ) async throws -> [Message] {
            listCallCount += 1
            for w in startedWaiters { w.resume() }
            startedWaiters.removeAll()
            return try await withCheckedThrowingContinuation { cont in
                pendingContinuations.append(cont)
            }
        }

        func sendText(
            recipientId: Int,
            body: String,
            clientTempId: String,
            token: String
        ) async throws -> Message {
            sendCallCount += 1
            lastSendTempId = clientTempId
            for w in sendStartedWaiters { w.resume() }
            sendStartedWaiters.removeAll()
            return try await withCheckedThrowingContinuation { cont in
                pendingSendContinuations.append(cont)
            }
        }

        func sendImage(
            recipientId: Int,
            mediaUrl: String,
            mediaWidth: Int,
            mediaHeight: Int,
            clientTempId: String,
            token: String
        ) async throws -> Message { fatalError("not used in race tests") }

        func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}

        /// 等到至少一个 list() 调用挂起后才返回。
        func waitUntilStarted() async {
            if listCallCount > 0 { return }
            await withCheckedContinuation { cont in
                startedWaiters.append(cont)
            }
        }

        /// 等到至少一个 sendText() 调用挂起后才返回。
        func waitUntilSendStarted() async {
            if sendCallCount > 0 { return }
            await withCheckedContinuation { cont in
                sendStartedWaiters.append(cont)
            }
        }

        /// 释放所有挂起的 list() 调用，令其返回 rows。
        func releaseAll() {
            let conts = pendingContinuations
            pendingContinuations.removeAll()
            for cont in conts { cont.resume(returning: rows) }
        }

        /// 释放所有挂起的 sendText()，返回指定服务端消息。
        func releaseSend(with message: Message) {
            let conts = pendingSendContinuations
            pendingSendContinuations.removeAll()
            for cont in conts { cont.resume(returning: message) }
        }
    }

    // MARK: - Fixtures

    private func makeConversation(id: Int = 5, peerId: Int = 9) -> Conversation {
        Conversation(
            id: id,
            createdAt: Date(),
            peer: UserProfile(id: peerId, username: "peer", displayName: nil, avatarUrl: nil),
            lastMessageBody: nil,
            lastMessageType: nil,
            lastMessageSenderId: nil,
            lastMessageAt: nil,
            lastReadMessageId: nil,
            unreadCount: 0
        )
    }

    private func msg(id: Int, convId: Int = 5, senderId: Int = 9, body: String = "hi") -> Message {
        Message(
            id: id,
            conversationId: convId,
            senderId: senderId,
            body: body,
            messageType: "text",
            mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
            clientTempId: nil
        )
    }

    // MARK: - Bug 1：load() 全量覆盖可能丢失 WS 消息

    @Test
    func peerMessageArrivingDuringInitialLoadIsNotLost() async {
        // load() 在 REST 网络请求期间挂起；对方发来一条 WS 消息。
        // 修复前：await 恢复后 messages = rows.reversed()… 全量赋值把 WS 消息覆盖掉。
        // 修复后：用 mergeLoadedMessages 合并，WS 消息被保留。
        let repo = BlockingRepo(rows: [msg(id: 1, body: "server msg")])
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 3,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )

        async let loading: Void = vm.load()

        // 等待 load() 挂在 messageRepo.list() 上
        await repo.waitUntilStarted()

        // 对方在 REST 等待期间发来消息
        vm.handleWSEvent(.messageNew(msg(id: 2, senderId: 9, body: "peer live msg")))
        #expect(vm.messages.count == 1, "WS 消息应当立即追加")

        // 释放网络请求，load() 继续执行
        await repo.releaseAll()
        await loading

        let ids = vm.messages.map(\.message.id).sorted()
        #expect(ids == [1, 2], "REST 加载完成后 WS 消息不应丢失")
    }

    @Test
    func pendingBubbleIsRemovedWhenInitialLoadAlreadyContainsConfirmedCopy() async {
        // 首屏 load() 挂起期间发送消息，本地先追加 pending。
        // 若首屏 REST 返回时已经包含这条服务端消息，随后 sendText 成功回包不应留下两条 confirmed。
        let repo = BlockingRepo(rows: [msg(id: 456, senderId: 3, body: "hi")])
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 3,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )

        async let loading: Void = vm.load()
        await repo.waitUntilStarted()

        let sendTask = Task { @MainActor in await vm.sendText("hi") }
        await repo.waitUntilSendStarted()

        #expect(vm.messages.count == 1, "发送后应先出现一条 pending 气泡")
        #expect(vm.messages[0].sendState == .pending)

        await repo.releaseAll()
        await loading

        #expect(vm.messages.count == 2, "首屏返回 confirmed 副本后，当前实现会暂时同时保留 pending")
        #expect(vm.messages.filter { $0.message.id == 456 }.count == 1)

        let tempId = await repo.lastSendTempId
        #expect(tempId != nil)

        await repo.releaseSend(with: Message(
            id: 456,
            conversationId: 5,
            senderId: 3,
            body: "hi",
            messageType: "text",
            mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_456),
            clientTempId: tempId
        ))
        await sendTask.value

        #expect(vm.messages.count == 1, "send 成功后应移除重复 pending，而不是留下两条 confirmed")
        #expect(vm.messages[0].message.id == 456)
        #expect(vm.messages[0].sendState == .confirmed)
    }

    // MARK: - Bug 3：load() 并发调用发出两次网络请求

    @Test
    func concurrentLoadCallsDoNotDoubleNetwork() async {
        // load() 没有 in-flight 防重入保护；WS ready 触发的 reconcileAfterReconnect → load()
        // 可在初始 load() 挂起期间再次进入 if messages.isEmpty 分支，导致两次 list() 调用。
        let repo = BlockingRepo(rows: [msg(id: 1)])
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 3,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )

        // 第一次 load()，挂在 list() 上
        async let loading1: Void = vm.load()
        await repo.waitUntilStarted()

        // 第二次 load() 并发进来；和测试同在 MainActor，yield 一次即可把执行权让给它，
        // 守卫正常时会立刻返回，不需要依赖不稳定的 sleep 采样。
        let task2 = Task { @MainActor in await vm.load() }
        await Task.yield()

        // 检查：修复后只有 1 次 list() 调用；修复前为 2 次
        let n = await repo.listCallCount
        #expect(n == 1, "第二次 load() 应当被 isLoadingInitial 守卫拦截，不发第二次网络请求")

        // 清理：释放所有挂起的调用，避免测试挂起
        await repo.releaseAll()
        await loading1
        await task2.value

        #expect(vm.phase == .loaded)
        #expect(vm.messages.count == 1)
    }
}
