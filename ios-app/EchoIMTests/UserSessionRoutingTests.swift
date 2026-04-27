import Foundation
import Testing
import SwiftData
@testable import EchoIM

@MainActor
@Suite
struct UserSessionRoutingTests {
    private struct Fixture {
        let session: UserSession
        let storeDir: URL
    }

    private func makeFixture() throws -> Fixture {
        let userId = Int.random(in: 900_000_000...999_999_999)
        let storeDir = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)")
        let session = try UserSession(
            userId: userId,
            apiClient: APIClient(),
            tokenLoader: { nil },
            onUnauthorized: {}
        )
        return Fixture(session: session, storeDir: storeDir)
    }

    private func withFixture<T>(
        _ body: @MainActor (Fixture) async throws -> T
    ) async throws -> T {
        var fixture: Fixture? = try makeFixture()
        let storeDir = fixture!.storeDir
        do {
            let result = try await body(fixture!)
            fixture = nil
            await Task.yield()
            try? FileManager.default.removeItem(at: storeDir)
            return result
        } catch {
            fixture = nil
            await Task.yield()
            try? FileManager.default.removeItem(at: storeDir)
            throw error
        }
    }

    @Test
    func presenceOnlineEventInsertsIntoPresenceStore() async throws {
        try await withFixture { fixture in
            fixture.session.wsClient._dispatchForTesting(
                .presenceOnline(UserIdPayload(userId: 7))
            )
            #expect(fixture.session.presenceStore.isOnline(7))
        }
    }

    @Test
    func presenceOfflineEventRemovesFromPresenceStore() async throws {
        try await withFixture { fixture in
            fixture.session.presenceStore.setOnline(7)
            fixture.session.wsClient._dispatchForTesting(
                .presenceOffline(UserIdPayload(userId: 7))
            )
            #expect(!fixture.session.presenceStore.isOnline(7))
        }
    }

    @Test
    func typingStartEventInsertsIntoTypingStore() async throws {
        try await withFixture { fixture in
            fixture.session.wsClient._dispatchForTesting(
                .typingStart(ConversationUserPayload(conversationId: 42, userId: 7))
            )
            #expect(fixture.session.typingStore.isTyping(42))
        }
    }

    @Test
    func typingStopEventRemovesFromTypingStore() async throws {
        try await withFixture { fixture in
            fixture.session.typingStore.handleTypingStart(conversationId: 42)
            fixture.session.wsClient._dispatchForTesting(
                .typingStop(ConversationUserPayload(conversationId: 42, userId: 7))
            )
            #expect(!fixture.session.typingStore.isTyping(42))
        }
    }

    @Test
    func wsReadyClearsPresenceStore() async throws {
        try await withFixture { fixture in
            fixture.session.presenceStore.setOnline(1)
            fixture.session.presenceStore.setOnline(2)
            fixture.session.wsClient._fireReadyForTesting()
            #expect(fixture.session.presenceStore.onlineUserIds.isEmpty)
        }
    }

    @Test
    func wsReadyClearsBeforeSubsequentPresenceOnlineEvents() async throws {
        try await withFixture { fixture in
            fixture.session.presenceStore.setOnline(99)

            fixture.session.wsClient._fireReadyForTesting()
            fixture.session.wsClient._dispatchForTesting(
                .presenceOnline(UserIdPayload(userId: 1))
            )
            fixture.session.wsClient._dispatchForTesting(
                .presenceOnline(UserIdPayload(userId: 2))
            )

            #expect(fixture.session.presenceStore.onlineUserIds == [1, 2])
            #expect(!fixture.session.presenceStore.isOnline(99))
        }
    }
}
