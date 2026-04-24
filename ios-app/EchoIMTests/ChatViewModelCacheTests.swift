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

        final class DelayedRepo: MessageRepository {
            func list(
                conversationId: Int,
                cursor: MessageCursor?,
                limit: Int?,
                token: String
            ) async throws -> [Message] {
                try await Task.sleep(nanoseconds: 200_000_000)
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
        }

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
            messageRepo: DelayedRepo(),
            wsClient: nil,
            conversationRepository: nil,
            messageStore: messageStore,
            metaStore: metaStore,
            tokenProvider: { "t" }
        )

        async let loading: Void = vm.load()

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.messages.count == 3)
        #expect(vm.messages.map(\.message.id) == [1, 2, 3])

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
}
