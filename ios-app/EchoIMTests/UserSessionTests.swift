import Testing
import Foundation
@testable import EchoIM

@Suite
struct UserSessionTests {
    @MainActor
    private func makeSession(userId: Int) throws -> UserSession {
        try UserSession(
            userId: userId,
            apiClient: APIClient(),
            tokenLoader: { nil },
            onUnauthorized: {}
        )
    }

    @MainActor
    @Test
    func bootstrapCreatesDirectoryAndExcludesFromBackup() async throws {
        let userId = Int.random(in: 900_000_000...999_999_999)
        let dir = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)")

        do {
            let session = try makeSession(userId: userId)
            _ = session

            #expect(FileManager.default.fileExists(atPath: dir.path))

            let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == true)
        }

        await Task.yield()
        try? FileManager.default.removeItem(at: dir)
    }

    @MainActor
    @Test
    func messageStoreAndConversationMetaStoreFactoriesReuseContainer() async throws {
        let userId = Int.random(in: 900_000_000...999_999_999)
        let dir = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)")

        do {
            let session = try makeSession(userId: userId)
            let store1 = session.messageStore()
            let store2 = session.messageStore()

            try await store1.append([
                Message(
                    id: 1,
                    conversationId: 1,
                    senderId: 1,
                    body: "hi",
                    messageType: "text",
                    mediaUrl: nil,
                    createdAt: Date(),
                    clientTempId: nil
                ),
            ])
            let read = try await store2.loadLatest(conversationId: 1, limit: 10)
            #expect(read.count == 1)
        }

        await Task.yield()
        try? FileManager.default.removeItem(at: dir)
    }
}
