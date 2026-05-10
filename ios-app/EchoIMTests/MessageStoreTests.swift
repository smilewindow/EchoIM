import Testing
import Foundation
import SwiftData
@testable import EchoIM

@Suite
struct MessageStoreTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CachedMessage.self, ConversationMeta.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeMessage(
        id: Int,
        conversationId: Int = 1,
        senderId: Int = 10,
        body: String? = nil
    ) -> Message {
        Message(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            body: body ?? "m-\(id)",
            messageType: "text",
            mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + id)),
            clientTempId: nil
        )
    }

    @Test
    func appendIsIdempotentOnDuplicateIds() async throws {
        let container = try makeContainer()
        let store = MessageStore(modelContainer: container)

        let m1 = makeMessage(id: 10)
        let m2 = makeMessage(id: 11)
        try await store.append([m1, m2])
        try await store.append([m1, m2])

        let latest = try await store.loadLatest(conversationId: 1, limit: 50)
        #expect(latest.count == 2)
        #expect(Set(latest.map(\.id)) == [10, 11])
    }

    @Test
    func appendSkipsDuplicateIdsWithinSameBatch() async throws {
        let container = try makeContainer()
        let store = MessageStore(modelContainer: container)

        let m1 = makeMessage(id: 10)
        let m2 = makeMessage(id: 11)
        // 同一批数据可能来自 REST/WS 重放合并；这里保护 SwiftData unique 约束不被重复 id 撞上。
        try await store.append([m1, m1, m2])

        let latest = try await store.loadLatest(conversationId: 1, limit: 50)
        #expect(latest.count == 2)
        #expect(latest.map(\.id) == [11, 10])
    }

    @Test
    func loadLatestReturnsNewestFirst() async throws {
        let container = try makeContainer()
        let store = MessageStore(modelContainer: container)

        try await store.append((1...10).map { makeMessage(id: $0) })

        let latest = try await store.loadLatest(conversationId: 1, limit: 3)
        #expect(latest.map(\.id) == [10, 9, 8])
    }

    @Test
    func loadOlderReturnsStrictlyBeforeCursor() async throws {
        let container = try makeContainer()
        let store = MessageStore(modelContainer: container)

        try await store.append((1...10).map { makeMessage(id: $0) })

        let older = try await store.loadOlder(conversationId: 1, before: 5, limit: 10)
        #expect(older.map(\.id) == [4, 3, 2, 1])
    }

    @Test
    func deleteAllPurgesAllConversations() async throws {
        let container = try makeContainer()
        let store = MessageStore(modelContainer: container)

        try await store.append([
            makeMessage(id: 1, conversationId: 1),
            makeMessage(id: 2, conversationId: 2),
        ])

        try await store.deleteAll()
        let c1 = try await store.loadLatest(conversationId: 1, limit: 50)
        let c2 = try await store.loadLatest(conversationId: 2, limit: 50)
        #expect(c1.isEmpty)
        #expect(c2.isEmpty)
    }
}
