import Foundation
import SwiftData
import Testing
@testable import EchoIM

private extension MessageStore {
    /// 测试专用：短暂占住 actor，稳定制造 `loadLatest()` 的等待窗口，
    /// 让 MainActor 有机会在 cache 读取期间注入 WS 消息。
    func testBusyWait(nanoseconds: UInt64) {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < nanoseconds {}
    }
}

@Suite
struct ChatViewModelCacheTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CachedMessage.self, ConversationMeta.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makePeer() -> UserProfile {
        UserProfile(id: 20, username: "peer", displayName: nil, avatarUrl: nil)
    }

    /// 测试用 meta snapshot；peer 字段自动补齐。
    private func metaSnap(
        conversationId: Int = 7,
        oldestCachedMessageId: Int? = nil,
        newestCachedMessageId: Int? = nil,
        lastReadMessageId: Int? = nil,
        unreadCount: Int = 0,
        lastMessageBody: String? = nil,
        lastMessageType: String? = nil,
        lastMessageAt: Date? = nil
    ) -> ConversationMetaSnapshot {
        ConversationMetaSnapshot(
            conversationId: conversationId,
            peerUserId: 20,
            peerUsername: "peer",
            peerDisplayName: nil,
            peerAvatarUrl: nil,
            oldestCachedMessageId: oldestCachedMessageId,
            newestCachedMessageId: newestCachedMessageId,
            lastReadMessageId: lastReadMessageId,
            unreadCount: unreadCount,
            lastMessageBody: lastMessageBody,
            lastMessageType: lastMessageType,
            lastMessageAt: lastMessageAt
        )
    }

    @MainActor
    @Test
    func loadRendersCachedMessagesBeforeNetwork() async throws {
        let container = try makeContainer()
        let messageStore = MessageStore(modelContainer: container)
        let metaStore = ConversationMetaStore(modelContainer: container)

        try await messageStore.append((1...3).map {
            Message(
                id: $0,
                conversationId: 7,
                senderId: 20,
                body: "cached-\($0)",
                messageType: "text",
                mediaUrl: nil,
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                clientTempId: nil
            )
        })
        try await metaStore.upsert(
            metaSnap(
                oldestCachedMessageId: 1,
                newestCachedMessageId: 3,
                lastReadMessageId: 3,
                unreadCount: 0,
                lastMessageBody: "cached-3",
                lastMessageType: "text",
                lastMessageAt: Date(timeIntervalSince1970: 1_700_000_003)
            )
        )

        actor BlockingRepo: MessageRepository {
            private var started = false
            private var startWaiters: [CheckedContinuation<Void, Never>] = []
            private var releaseWaiter: CheckedContinuation<Void, Never>?
            private var released = false

            func list(
                conversationId: Int,
                cursor: MessageCursor?,
                limit: Int?,
                token: String
            ) async throws -> [Message] {
                started = true
                startWaiters.forEach { $0.resume() }
                startWaiters.removeAll()

                await withCheckedContinuation { continuation in
                    if released {
                        continuation.resume()
                    } else {
                        releaseWaiter = continuation
                    }
                }
                return []
            }

            func sendText(
                recipientId: Int,
                body: String,
                clientTempId: String,
                token: String
            ) async throws -> Message {
                fatalError()
            }

            func sendImage(
                recipientId: Int,
                mediaUrl: String,
                mediaWidth: Int,
                mediaHeight: Int,
                clientTempId: String,
                token: String
            ) async throws -> Message {
                fatalError()
            }

            func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}

            func waitUntilStarted() async {
                if started {
                    return
                }

                await withCheckedContinuation { continuation in
                    startWaiters.append(continuation)
                }
            }

            func release() {
                released = true
                releaseWaiter?.resume()
                releaseWaiter = nil
            }
        }

        let repo = BlockingRepo()
        let conversation = Conversation(
            id: 7,
            createdAt: Date(),
            peer: makePeer(),
            lastMessageBody: "cached-3",
            lastMessageType: "text",
            lastMessageSenderId: 20,
            lastMessageAt: Date(),
            lastReadMessageId: 3,
            unreadCount: 0
        )
        let vm = ChatViewModel(
            route: .conversation(conversation),
            currentUserId: 10,
            messageRepo: repo,
            wsClient: nil,
            conversationRepository: nil,
            messageStore: messageStore,
            metaStore: metaStore,
            tokenProvider: { "t" }
        )

        async let loading: Void = vm.load()

        await repo.waitUntilStarted()
        #expect(vm.messages.count == 3)
        #expect(vm.messages.map(\.message.id) == [1, 2, 3])

        await repo.release()
        await loading
        #expect(vm.phase == .loaded)
    }

    @MainActor
    @Test
    func cacheHitMergePreservesPeerWSMessageArrivingDuringCacheLoad() async throws {
        let container = try makeContainer()
        let messageStore = MessageStore(modelContainer: container)

        try await messageStore.append([
            Message(
                id: 1,
                conversationId: 7,
                senderId: 20,
                body: "cached-1",
                messageType: "text",
                mediaUrl: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_001),
                clientTempId: nil
            )
        ])

        actor BlockingRepo: MessageRepository {
            private var started = false
            private var startWaiters: [CheckedContinuation<Void, Never>] = []
            private var releaseWaiter: CheckedContinuation<Void, Never>?
            private var released = false

            func list(
                conversationId: Int,
                cursor: MessageCursor?,
                limit: Int?,
                token: String
            ) async throws -> [Message] {
                started = true
                startWaiters.forEach { $0.resume() }
                startWaiters.removeAll()

                await withCheckedContinuation { continuation in
                    if released {
                        continuation.resume()
                    } else {
                        releaseWaiter = continuation
                    }
                }
                return []
            }

            func sendText(
                recipientId: Int,
                body: String,
                clientTempId: String,
                token: String
            ) async throws -> Message {
                fatalError()
            }

            func sendImage(
                recipientId: Int,
                mediaUrl: String,
                mediaWidth: Int,
                mediaHeight: Int,
                clientTempId: String,
                token: String
            ) async throws -> Message {
                fatalError()
            }

            func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}

            func waitUntilStarted() async {
                if started {
                    return
                }

                await withCheckedContinuation { continuation in
                    startWaiters.append(continuation)
                }
            }

            func release() {
                released = true
                releaseWaiter?.resume()
                releaseWaiter = nil
            }
        }

        let repo = BlockingRepo()
        let vm = ChatViewModel(
            route: .conversation(
                Conversation(
                    id: 7,
                    createdAt: Date(),
                    peer: makePeer(),
                    lastMessageBody: nil,
                    lastMessageType: nil,
                    lastMessageSenderId: nil,
                    lastMessageAt: nil,
                    lastReadMessageId: nil,
                    unreadCount: 0
                )
            ),
            currentUserId: 10,
            messageRepo: repo,
            wsClient: nil,
            conversationRepository: nil,
            messageStore: messageStore,
            metaStore: nil,
            tokenProvider: { "t" }
        )

        let cacheBlocker = Task { await messageStore.testBusyWait(nanoseconds: 50_000_000) }
        async let loading: Void = vm.load()

        // `load()` 此时卡在 `await messageStore.loadLatest(...)` 上，MainActor 空出来后
        // 注入一条对方 WS 消息，验证 cache 分支的 mergeLoadedMessages 也能保住它。
        await Task.yield()
        vm.handleWSEvent(
            .messageNew(
                Message(
                    id: 2,
                    conversationId: 7,
                    senderId: 20,
                    body: "peer-live",
                    messageType: "text",
                    mediaUrl: nil,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_002),
                    clientTempId: nil
                )
            )
        )
        #expect(vm.messages.count == 1, "WS 消息应当能先进入列表")

        await cacheBlocker.value
        await repo.waitUntilStarted()

        #expect(vm.messages.map(\.message.id) == [1, 2], "cache 命中分支也应保留等待期间到达的 WS 消息")

        await repo.release()
        await loading
        #expect(vm.phase == .loaded)
    }

    @MainActor
    @Test
    func loadWritesNetworkResultToCache() async throws {
        let container = try makeContainer()
        let messageStore = MessageStore(modelContainer: container)
        let metaStore = ConversationMetaStore(modelContainer: container)

        final class StubRepo: MessageRepository {
            func list(
                conversationId: Int,
                cursor: MessageCursor?,
                limit: Int?,
                token: String
            ) async throws -> [Message] {
                (1...10).reversed().map {
                    Message(
                        id: $0,
                        conversationId: 7,
                        senderId: 20,
                        body: "m-\($0)",
                        messageType: "text",
                        mediaUrl: nil,
                        createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                        clientTempId: nil
                    )
                }
            }

            func sendText(
                recipientId: Int,
                body: String,
                clientTempId: String,
                token: String
            ) async throws -> Message {
                fatalError()
            }

            func sendImage(
                recipientId: Int,
                mediaUrl: String,
                mediaWidth: Int,
                mediaHeight: Int,
                clientTempId: String,
                token: String
            ) async throws -> Message {
                fatalError()
            }

            func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
        }

        let vm = ChatViewModel(
            route: .conversation(
                Conversation(
                    id: 7,
                    createdAt: Date(),
                    peer: makePeer(),
                    lastMessageBody: nil,
                    lastMessageType: nil,
                    lastMessageSenderId: nil,
                    lastMessageAt: nil,
                    lastReadMessageId: nil,
                    unreadCount: 0
                )
            ),
            currentUserId: 10,
            messageRepo: StubRepo(),
            wsClient: nil,
            conversationRepository: nil,
            messageStore: messageStore,
            metaStore: metaStore,
            tokenProvider: { "t" }
        )

        await vm.load()

        let cached = try await messageStore.loadLatest(conversationId: 7, limit: 50)
        #expect(cached.count == 10)
        let meta = try await metaStore.load(conversationId: 7)
        #expect(meta?.oldestCachedMessageId == 1)
        #expect(meta?.newestCachedMessageId == 10)
    }

    @MainActor
    @Test
    func refetchLoopsUntilSmallPage() async throws {
        let container = try makeContainer()
        let messageStore = MessageStore(modelContainer: container)
        let metaStore = ConversationMetaStore(modelContainer: container)

        actor PagedRepo: MessageRepository {
            private(set) var calls = 0

            func list(
                conversationId: Int,
                cursor: MessageCursor?,
                limit: Int?,
                token: String
            ) async throws -> [Message] {
                calls += 1
                guard case let .after(anchor)? = cursor else { return [] }
                let upperBound = 220
                let upper = min(anchor + 50, upperBound)
                if upper <= anchor { return [] }
                return (anchor + 1...upper).map {
                    Message(
                        id: $0,
                        conversationId: 7,
                        senderId: 20,
                        body: "m-\($0)",
                        messageType: "text",
                        mediaUrl: nil,
                        createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                        clientTempId: nil
                    )
                }
            }

            func sendText(
                recipientId: Int,
                body: String,
                clientTempId: String,
                token: String
            ) async throws -> Message {
                fatalError()
            }

            func sendImage(
                recipientId: Int,
                mediaUrl: String,
                mediaWidth: Int,
                mediaHeight: Int,
                clientTempId: String,
                token: String
            ) async throws -> Message {
                fatalError()
            }

            func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
        }

        try await messageStore.append((51...100).map {
            Message(
                id: $0,
                conversationId: 7,
                senderId: 20,
                body: "m-\($0)",
                messageType: "text",
                mediaUrl: nil,
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                clientTempId: nil
            )
        })
        try await metaStore.upsert(
            metaSnap(
                oldestCachedMessageId: 51,
                newestCachedMessageId: 100,
                lastReadMessageId: 100,
                unreadCount: 0,
                lastMessageBody: "m-100",
                lastMessageType: "text",
                lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        )

        let conversation = Conversation(
            id: 7,
            createdAt: Date(),
            peer: makePeer(),
            lastMessageBody: "m-100",
            lastMessageType: "text",
            lastMessageSenderId: 20,
            lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100),
            lastReadMessageId: 100,
            unreadCount: 0
        )
        let repo = PagedRepo()
        let vm = ChatViewModel(
            route: .conversation(conversation),
            currentUserId: 10,
            messageRepo: repo,
            wsClient: nil,
            conversationRepository: nil,
            messageStore: messageStore,
            metaStore: metaStore,
            tokenProvider: { "t" }
        )

        await vm.refetchMissedMessages()

        let n = await repo.calls
        #expect(n == 3)
        let cached = try await messageStore.loadLatest(conversationId: 7, limit: 200)
        #expect(cached.count == 170)
        #expect(cached.first?.id == 220)
        let meta = try await metaStore.load(conversationId: 7)
        #expect(meta?.oldestCachedMessageId == 51)
        #expect(meta?.newestCachedMessageId == 220)
    }

    @MainActor
    @Test
    func loadOlderFullyServedByCacheSkipsNetwork() async throws {
        let container = try makeContainer()
        let messageStore = MessageStore(modelContainer: container)
        let metaStore = ConversationMetaStore(modelContainer: container)

        // 缓存已有完整 1...100：首屏渲染 51...100，上滑直接吃本地 1...50。
        try await messageStore.append((1...100).map {
            Message(
                id: $0,
                conversationId: 7,
                senderId: 20,
                body: "m-\($0)",
                messageType: "text",
                mediaUrl: nil,
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                clientTempId: nil
            )
        })
        try await metaStore.upsert(
            metaSnap(
                oldestCachedMessageId: 1,
                newestCachedMessageId: 100,
                lastReadMessageId: 100,
                unreadCount: 0,
                lastMessageBody: "m-100",
                lastMessageType: "text",
                lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        )

        actor StrictRepo: MessageRepository {
            private(set) var calls = 0

            func list(
                conversationId: Int,
                cursor: MessageCursor?,
                limit: Int?,
                token: String
            ) async throws -> [Message] {
                calls += 1
                return []
            }

            func sendText(
                recipientId: Int,
                body: String,
                clientTempId: String,
                token: String
            ) async throws -> Message {
                fatalError()
            }

            func sendImage(
                recipientId: Int,
                mediaUrl: String,
                mediaWidth: Int,
                mediaHeight: Int,
                clientTempId: String,
                token: String
            ) async throws -> Message {
                fatalError()
            }

            func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}

            func resetCalls() {
                calls = 0
            }
        }

        let conversation = Conversation(
            id: 7,
            createdAt: Date(),
            peer: makePeer(),
            lastMessageBody: "m-100",
            lastMessageType: "text",
            lastMessageSenderId: 20,
            lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100),
            lastReadMessageId: 100,
            unreadCount: 0
        )
        let repo = StrictRepo()
        let vm = ChatViewModel(
            route: .conversation(conversation),
            currentUserId: 10,
            messageRepo: repo,
            wsClient: nil,
            conversationRepository: nil,
            messageStore: messageStore,
            metaStore: metaStore,
            tokenProvider: { "t" }
        )

        await vm.load()
        #expect(vm.messages.count == 50)
        #expect(vm.messages.first?.message.id == 51)
        #expect(vm.messages.last?.message.id == 100)

        await repo.resetCalls()
        await vm.loadOlder()

        let n = await repo.calls
        #expect(n == 0)
        #expect(vm.messages.count == 100)
        #expect(vm.messages.first?.message.id == 1)
    }

    @MainActor
    @Test
    func loadOlderPartialCacheHitsSupplementsFromRemote() async throws {
        let container = try makeContainer()
        let messageStore = MessageStore(modelContainer: container)
        let metaStore = ConversationMetaStore(modelContainer: container)

        // 缓存只有 41...100：上滑先用本地 41...50，再向远端补 1...40。
        try await messageStore.append((41...100).map {
            Message(
                id: $0,
                conversationId: 7,
                senderId: 20,
                body: "m-\($0)",
                messageType: "text",
                mediaUrl: nil,
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                clientTempId: nil
            )
        })
        try await metaStore.upsert(
            metaSnap(
                oldestCachedMessageId: 41,
                newestCachedMessageId: 100,
                lastReadMessageId: 100,
                unreadCount: 0,
                lastMessageBody: "m-100",
                lastMessageType: "text",
                lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        )

        actor RecordingRepo: MessageRepository {
            private(set) var lastBeforeAnchor: Int?
            private(set) var lastLimit: Int?
            private(set) var beforeCalls = 0

            func list(
                conversationId: Int,
                cursor: MessageCursor?,
                limit: Int?,
                token: String
            ) async throws -> [Message] {
                switch cursor {
                case .before(let anchor):
                    beforeCalls += 1
                    lastBeforeAnchor = anchor
                    lastLimit = limit
                    let count = min(limit ?? 50, anchor - 1)
                    guard count > 0 else { return [] }
                    return stride(from: anchor - 1, through: anchor - count, by: -1).map {
                        Message(
                            id: $0,
                            conversationId: 7,
                            senderId: 20,
                            body: "m-\($0)",
                            messageType: "text",
                            mediaUrl: nil,
                            createdAt: Date(
                                timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)
                            ),
                            clientTempId: nil
                        )
                    }
                case .after, .none:
                    return []
                }
            }

            func sendText(
                recipientId: Int,
                body: String,
                clientTempId: String,
                token: String
            ) async throws -> Message {
                fatalError()
            }

            func sendImage(
                recipientId: Int,
                mediaUrl: String,
                mediaWidth: Int,
                mediaHeight: Int,
                clientTempId: String,
                token: String
            ) async throws -> Message {
                fatalError()
            }

            func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
        }

        let conversation = Conversation(
            id: 7,
            createdAt: Date(),
            peer: makePeer(),
            lastMessageBody: "m-100",
            lastMessageType: "text",
            lastMessageSenderId: 20,
            lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100),
            lastReadMessageId: 100,
            unreadCount: 0
        )
        let repo = RecordingRepo()
        let vm = ChatViewModel(
            route: .conversation(conversation),
            currentUserId: 10,
            messageRepo: repo,
            wsClient: nil,
            conversationRepository: nil,
            messageStore: messageStore,
            metaStore: metaStore,
            tokenProvider: { "t" }
        )

        await vm.load()
        await vm.loadOlder()

        let anchor = await repo.lastBeforeAnchor
        let limit = await repo.lastLimit
        let beforeCalls = await repo.beforeCalls
        #expect(beforeCalls == 1)
        #expect(anchor == 41)
        #expect(limit == 40)
        #expect(vm.messages.count == 100)
        #expect(vm.messages.first?.message.id == 1)

        let cached = try await messageStore.loadLatest(conversationId: 7, limit: 200)
        #expect(cached.count == 100)
    }

    @MainActor
    @Test
    func confirmedImageMessageWritesThroughToCache() async throws {
        let container = try makeContainer()
        let messageStore = MessageStore(modelContainer: container)
        let metaStore = ConversationMetaStore(modelContainer: container)

        let upload = MockUploadRepo()
        upload.uploadResult = UploadedMessageImage(
            mediaUrl: "/uploads/messages/3-2.jpg",
            mediaWidth: 1600,
            mediaHeight: 1200
        )
        let messages = MockMessageRepo()
        messages.sendImageResult = .success(
            Message(
                id: 700,
                conversationId: 5,
                senderId: 3,
                body: nil,
                messageType: "image",
                mediaUrl: "/uploads/messages/3-2.jpg",
                createdAt: Date(),
                clientTempId: nil
            )
        )

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages,
            messageStore: messageStore,
            metaStore: metaStore
        )

        await vm.sendCompressedImage(data: Data([0xFF]), width: 10, height: 10)

        var cached: [Message] = []
        for _ in 0..<50 {
            cached = try await messageStore.loadLatest(conversationId: 5, limit: 10)
            if cached.contains(where: { $0.id == 700 }) {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(cached.contains { $0.id == 700 && $0.mediaUrl == "/uploads/messages/3-2.jpg" })

        let meta = try #require(try await metaStore.load(conversationId: 5))
        #expect(meta.lastMessageType == "image")
        #expect(meta.newestCachedMessageId == 700)
    }

    @MainActor
    @Test
    func pendingImageBubbleIsNotWrittenToCache() async throws {
        let container = try makeContainer()
        let messageStore = MessageStore(modelContainer: container)
        let metaStore = ConversationMetaStore(modelContainer: container)

        let upload = SuspendableUploadRepo()
        let messages = MockMessageRepo()

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages,
            messageStore: messageStore,
            metaStore: metaStore
        )

        let task = Task {
            await vm.sendCompressedImage(data: Data([0xFF, 0xD8]), width: 10, height: 10)
        }
        await Task.yield()
        await Task.yield()

        let cached = try await messageStore.loadLatest(conversationId: 5, limit: 10)
        #expect(cached.isEmpty, "pending image 不应进入 SwiftData（id 是负数 + media_url nil 会破坏不变式）")

        upload.resume(with: "/uploads/messages/3-3.jpg")
        await task.value
    }
}
