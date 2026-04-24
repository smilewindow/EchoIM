import Foundation
import SwiftData
import Testing
@testable import EchoIM

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
}
