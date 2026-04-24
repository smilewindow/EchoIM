import Foundation
import SwiftData
import Testing
@testable import EchoIM

@Suite
struct ConversationsListViewModelCacheTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CachedMessage.self, ConversationMeta.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// 测试用 snapshot：peer 字段给一个“看得出是好友 99”的值。
    private func snap(
        conversationId: Int,
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
            peerUserId: 99,
            peerUsername: "peer99",
            peerDisplayName: "Peer 99",
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
    func loadRendersCachedMetaBeforeNetwork() async throws {
        let container = try makeContainer()
        let metaStore = ConversationMetaStore(modelContainer: container)
        try await metaStore.upsert(
            snap(
                conversationId: 1,
                oldestCachedMessageId: 1,
                newestCachedMessageId: 5,
                lastReadMessageId: 3,
                unreadCount: 2,
                lastMessageBody: "cached",
                lastMessageType: "text",
                lastMessageAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        actor BlockingRepo: ConversationRepository {
            private var started = false
            private var startWaiters: [CheckedContinuation<Void, Never>] = []
            private var releaseWaiter: CheckedContinuation<Void, Never>?
            private var released = false

            func list(token: String) async throws -> [Conversation] {
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
        let vm = ConversationsListViewModel(
            repository: repo,
            metaStore: metaStore,
            tokenProvider: { "t" },
            currentUserId: { 10 }
        )

        async let loading: Void = vm.load()

        await repo.waitUntilStarted()
        #expect(vm.conversations.count == 1)
        #expect(vm.conversations.first?.lastMessageBody == "cached")
        #expect(vm.conversations.first?.peer.username == "peer99")

        await repo.release()
        await loading
        #expect(vm.conversations.isEmpty)
    }

    @MainActor
    @Test
    func refreshWritesBackToMetaStore() async throws {
        let container = try makeContainer()
        let metaStore = ConversationMetaStore(modelContainer: container)

        final class StubRepo: ConversationRepository {
            func list(token: String) async throws -> [Conversation] {
                let peer = UserProfile(id: 99, username: "p", displayName: nil, avatarUrl: nil)
                return [
                    Conversation(
                        id: 7,
                        createdAt: Date(),
                        peer: peer,
                        lastMessageBody: "fresh",
                        lastMessageType: "text",
                        lastMessageSenderId: 99,
                        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_500),
                        lastReadMessageId: 100,
                        unreadCount: 3
                    ),
                ]
            }
        }

        let vm = ConversationsListViewModel(
            repository: StubRepo(),
            metaStore: metaStore,
            tokenProvider: { "t" },
            currentUserId: { 10 }
        )

        await vm.load()

        let snap = try await metaStore.load(conversationId: 7)
        #expect(snap?.lastMessageBody == "fresh")
        #expect(snap?.unreadCount == 3)
    }
}
