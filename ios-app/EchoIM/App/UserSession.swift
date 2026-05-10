import Foundation
import SwiftData

/// 一个登录用户对应一个 UserSession。P4 起，按 userId 分库的 SwiftData cache、
/// WebSocketClient，以及会话相关 repository 都挂在这里。
@MainActor
final class UserSession {
    let userId: Int
    let modelContainer: ModelContainer
    /// ModelContainer 建好后同步读一次会话缓存，供 ConversationsListView 首帧直接使用。
    /// 后续网络刷新由 ViewModel 负责，此属性不再更新。
    let cachedConversationsAtLaunch: [Conversation]
    private(set) var wsClient: WebSocketClient

    // P6：在线状态 / 输入指示 store（不变式 1：store 不直接订阅 WS，由此处路由）
    let presenceStore: PresenceStore
    let typingStore: TypingStore
    private var routingSubscriptions: [WSSubscription] = []

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

        let schema = Schema([CachedMessage.self, ConversationMeta.self, CachedFriend.self])
        let config = ModelConfiguration(url: storeURL)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            // P4 是首次建库，不做迁移；开发期 schema 不匹配时删库重建。
            Log.warning(.cache, "schema mismatch – deleting and rebuilding cache: \(error)")
            try? FileManager.default.removeItem(at: storeDir)
            try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            try Self.excludeFromBackup(storeDir)
            modelContainer = try ModelContainer(for: schema, configurations: config)
        }

        let _ctx = ModelContext(modelContainer)
        let _desc = FetchDescriptor<ConversationMeta>(
            sortBy: [SortDescriptor(\.lastMessageAt, order: .reverse)]
        )
        cachedConversationsAtLaunch = (try? _ctx.fetch(_desc))?
            .map { $0.snapshot() }
            .map(Conversation.fromCachedMeta) ?? []
        Log.info(.cache, "launch hydration: \(cachedConversationsAtLaunch.count) conversations")
        wsClient = WebSocketClient(
            tokenProvider: tokenLoader,
            onUnauthorized: { Task { await onUnauthorized() } }
        )

        presenceStore = PresenceStore()
        typingStore = TypingStore()

        // 把 wsClient 上的事件路由到对应 store（不变式 1）。
        routingSubscriptions.append(
            wsClient.subscribe { [presenceStore, typingStore] event in
                Log.debug(.app, "routing \(event)")
                switch event {
                case .presenceOnline(let payload):
                    presenceStore.setOnline(payload.userId)
                case .presenceOffline(let payload):
                    presenceStore.setOffline(payload.userId)
                case .typingStart(let payload):
                    typingStore.handleTypingStart(conversationId: payload.conversationId)
                case .typingStop(let payload):
                    typingStore.handleTypingStop(conversationId: payload.conversationId)
                default:
                    break
                }
            }
        )
        routingSubscriptions.append(
            wsClient.onReady { [presenceStore] in
                // 设计 §7.5 step 5：先清空，让后续 presence.online 重建集合（不变式 3）。
                presenceStore.clearAll()
            }
        )
    }

    /// P6：业务层调用；wsClient 内部已有 .ready state guard，非 ready 状态静默丢弃。
    func sendTyping(conversationId: Int, isStart: Bool) {
        wsClient.sendTyping(conversationId: conversationId, isStart: isStart)
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

    func friendCacheStore() -> FriendCacheStore {
        FriendCacheStore(modelContainer: modelContainer)
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
