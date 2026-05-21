import Foundation
import Testing
import SwiftData
@testable import EchoIM

@MainActor
@Suite
struct UserSessionRoutingTests {
    final class RecordingMessageSoundPlayer: MessageSoundPlaying {
        private(set) var playCount = 0

        func playIncomingMessageSound() {
            playCount += 1
        }
    }

    private struct Fixture {
        let session: UserSession
        let storeDir: URL
        let soundPlayer: RecordingMessageSoundPlayer
        let defaults: UserDefaults
        let defaultsName: String
    }

    private func makeFixture() throws -> Fixture {
        let userId = Int.random(in: 900_000_000...999_999_999)
        let storeDir = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)")
        let soundPlayer = RecordingMessageSoundPlayer()
        let defaultsName = "UserSessionRoutingTests.\(userId)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        let session = try UserSession(
            userId: userId,
            apiClient: APIClient(),
            tokenLoader: { nil },
            onUnauthorized: {},
            messageSoundPlayer: soundPlayer,
            messageSoundDefaults: defaults
        )
        return Fixture(
            session: session,
            storeDir: storeDir,
            soundPlayer: soundPlayer,
            defaults: defaults,
            defaultsName: defaultsName
        )
    }

    private func withFixture<T>(
        _ body: @MainActor (Fixture) async throws -> T
    ) async throws -> T {
        var fixture: Fixture? = try makeFixture()
        let storeDir = fixture!.storeDir
        let defaultsName = fixture!.defaultsName
        let defaults = fixture!.defaults
        do {
            let result = try await body(fixture!)
            fixture = nil
            await Task.yield()
            try? FileManager.default.removeItem(at: storeDir)
            defaults.removePersistentDomain(forName: defaultsName)
            return result
        } catch {
            fixture = nil
            await Task.yield()
            try? FileManager.default.removeItem(at: storeDir)
            defaults.removePersistentDomain(forName: defaultsName)
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

    @Test
    func incomingMessageFromPeerPlaysSound() async throws {
        try await withFixture { fixture in
            fixture.session.wsClient._dispatchForTesting(
                .messageNew(
                    Message(
                        id: 101,
                        conversationId: 9,
                        senderId: fixture.session.userId + 1,
                        body: "hello",
                        messageType: "text",
                        mediaUrl: nil,
                        createdAt: Date(),
                        clientTempId: nil
                    )
                )
            )

            #expect(fixture.soundPlayer.playCount == 1)
        }
    }

    @Test
    func ownMessageDoesNotPlaySound() async throws {
        try await withFixture { fixture in
            fixture.session.wsClient._dispatchForTesting(
                .messageNew(
                    Message(
                        id: 102,
                        conversationId: 9,
                        senderId: fixture.session.userId,
                        body: "echo",
                        messageType: "text",
                        mediaUrl: nil,
                        createdAt: Date(),
                        clientTempId: "temp-1"
                    )
                )
            )

            #expect(fixture.soundPlayer.playCount == 0)
        }
    }

    @Test
    func incomingMessageDoesNotPlaySoundWhenDisabled() async throws {
        try await withFixture { fixture in
            MessageSoundSettings.setEnabled(false, defaults: fixture.defaults)

            fixture.session.wsClient._dispatchForTesting(
                .messageNew(
                    Message(
                        id: 103,
                        conversationId: 9,
                        senderId: fixture.session.userId + 1,
                        body: "quiet",
                        messageType: "text",
                        mediaUrl: nil,
                        createdAt: Date(),
                        clientTempId: nil
                    )
                )
            )

            #expect(fixture.soundPlayer.playCount == 0)
        }
    }
}
