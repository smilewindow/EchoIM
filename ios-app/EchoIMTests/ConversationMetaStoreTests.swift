import Testing
import Foundation
import SwiftData
@testable import EchoIM

@Suite
struct ConversationMetaStoreTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CachedMessage.self, ConversationMeta.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func snap(
        conversationId: Int,
        peerUserId: Int = 999,
        peerUsername: String? = nil,
        peerDisplayName: String? = nil,
        peerAvatarUrl: String? = nil,
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
            peerUserId: peerUserId,
            peerUsername: peerUsername ?? "peer\(conversationId)",
            peerDisplayName: peerDisplayName,
            peerAvatarUrl: peerAvatarUrl,
            oldestCachedMessageId: oldestCachedMessageId,
            newestCachedMessageId: newestCachedMessageId,
            lastReadMessageId: lastReadMessageId,
            unreadCount: unreadCount,
            lastMessageBody: lastMessageBody,
            lastMessageType: lastMessageType,
            lastMessageAt: lastMessageAt
        )
    }

    @Test
    func upsertCreatesAndOverwrites() async throws {
        let container = try makeContainer()
        let store = ConversationMetaStore(modelContainer: container)

        try await store.upsert(
            snap(
                conversationId: 7,
                peerUserId: 99,
                peerUsername: "p1",
                peerDisplayName: "Peer 1",
                oldestCachedMessageId: 1,
                newestCachedMessageId: 10,
                lastReadMessageId: 5,
                unreadCount: 5,
                lastMessageBody: "hi",
                lastMessageType: "text",
                lastMessageAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        let snap1 = try await store.load(conversationId: 7)
        #expect(snap1?.unreadCount == 5)
        #expect(snap1?.peerUsername == "p1")

        try await store.upsert(
            snap(
                conversationId: 7,
                peerUserId: 100,
                peerUsername: "p2",
                peerDisplayName: "Peer 2",
                oldestCachedMessageId: 1,
                newestCachedMessageId: 12,
                lastReadMessageId: 12,
                unreadCount: 0,
                lastMessageBody: "bye",
                lastMessageType: "text",
                lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        )

        let snap2 = try await store.load(conversationId: 7)
        #expect(snap2?.unreadCount == 0)
        #expect(snap2?.newestCachedMessageId == 12)
        #expect(snap2?.lastMessageBody == "bye")
        #expect(snap2?.peerUserId == 100)
        #expect(snap2?.peerUsername == "p2")
    }

    @Test
    func loadAllReturnsAllRows() async throws {
        let container = try makeContainer()
        let store = ConversationMetaStore(modelContainer: container)

        try await store.upsert(snap(conversationId: 1))
        try await store.upsert(snap(conversationId: 2))

        let all = try await store.loadAll()
        #expect(Set(all.map(\.conversationId)) == [1, 2])
    }

    @Test
    func deleteAllClearsRows() async throws {
        let container = try makeContainer()
        let store = ConversationMetaStore(modelContainer: container)

        try await store.upsert(snap(conversationId: 1))
        try await store.deleteAll()

        #expect(try await store.loadAll().isEmpty)
        #expect(try await store.load(conversationId: 1) == nil)
    }
}
