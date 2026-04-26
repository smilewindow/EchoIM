import Foundation
import SwiftData

/// 一个登录用户对应一个 UserSession。P4 起，按 userId 分库的 SwiftData cache、
/// WebSocketClient，以及会话相关 repository 都挂在这里。
@MainActor
final class UserSession {
    let userId: Int
    let modelContainer: ModelContainer
    private(set) var wsClient: WebSocketClient

    private let apiClient: APIClient
    private let tokenLoader: @MainActor () -> String?
    private let onUnauthorized: @MainActor () async -> Void

    init(
        userId: Int,
        apiClient: APIClient,
        tokenLoader: @escaping @MainActor () -> String?,
        onUnauthorized: @escaping @MainActor () async -> Void
    ) throws {
        self.userId = userId
        self.apiClient = apiClient
        self.tokenLoader = tokenLoader
        self.onUnauthorized = onUnauthorized

        let storeURL = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)/cache.sqlite")
        let storeDir = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        try Self.excludeFromBackup(storeDir)

        let schema = Schema([CachedMessage.self, ConversationMeta.self])
        let config = ModelConfiguration(url: storeURL)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            // P4 是首次建库，不做迁移；开发期 schema 不匹配时删库重建。
            try? FileManager.default.removeItem(at: storeDir)
            try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            try Self.excludeFromBackup(storeDir)
            modelContainer = try ModelContainer(for: schema, configurations: config)
        }

        wsClient = WebSocketClient(
            tokenProvider: tokenLoader,
            onUnauthorized: { Task { await onUnauthorized() } }
        )
    }

    func makeMessageRepository() -> MessageRepository {
        MessageRepositoryImpl(api: apiClient)
    }

    func makeUploadRepository() -> UploadRepository {
        UploadRepositoryImpl(api: apiClient)
    }

    func makeConversationRepository() -> ConversationRepository {
        ConversationRepositoryImpl(api: apiClient)
    }

    func messageStore() -> MessageStore {
        MessageStore(modelContainer: modelContainer)
    }

    func conversationMetaStore() -> ConversationMetaStore {
        ConversationMetaStore(modelContainer: modelContainer)
    }

    func connectWebSocketIfNeeded() {
        wsClient.connectIfNeeded()
    }

    func disconnectWebSocket(reason: WSDisconnectReason) {
        wsClient.disconnect(reason: reason)
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
