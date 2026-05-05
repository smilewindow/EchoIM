import Foundation
import Nuke
import Observation

/// 登录态无关的资源（token、API client）+ 指向当前登录用户的 `UserSession`。
/// 登出 / token 失效时整体释放 session（设计 §2.2）。
@MainActor
@Observable
final class AppContainer {
    let tokenStore: KeychainTokenStore
    let apiClient: APIClient
    var currentUser: AuthenticatedUser?
    var sessionExpiredNoticeID: UUID?

    /// 当前登录用户的会话。未登录时 nil。P4 起 wsClient / 会话相关 repo 都从这里取。
    private(set) var session: UserSession?

    /// 仅 UI 测试参数 `-uitest-reset-keychain` 会把它设为 true。
    private let resetKeychainOnLaunch: Bool

    init(
        tokenStore: KeychainTokenStore? = nil,
        apiClient: APIClient? = nil,
        resetKeychainOnLaunch: Bool = false
    ) {
        self.tokenStore = tokenStore ?? KeychainTokenStore()
        self.apiClient = apiClient ?? APIClient()
        self.resetKeychainOnLaunch = resetKeychainOnLaunch

        configureImagePipelineCache()
    }

    // MARK: - Configuration

    private func configureImagePipelineCache() {
        let config = ImagePipeline.Configuration.withDataCache(
            name: "com.echoim.MessageImages",
            sizeLimit: 1024 * 1024 * 1024
        )
        ImagePipeline.shared = ImagePipeline(configuration: config)
    }

    // MARK: - Stateless repositories（不绑定 session）

    func makeAuthRepository() -> AuthRepository {
        AuthRepositoryImpl(api: apiClient, tokenStore: tokenStore)
    }

    func makeUserRepository() -> UserRepository {
        UserRepositoryImpl(api: apiClient)
    }

    func makeFriendRepository() -> FriendRepository {
        FriendRepositoryImpl(api: apiClient)
    }

    func makeFriendRequestRepository() -> FriendRequestRepository {
        FriendRequestRepositoryImpl(api: apiClient)
    }

    // MARK: - Session lifecycle

    func bootstrap() {
        if resetKeychainOnLaunch {
            try? tokenStore.clear()
            currentUser = nil
            sessionExpiredNoticeID = nil
            session = nil
            return
        }

        guard let stored = try? tokenStore.load() else {
            currentUser = nil
            sessionExpiredNoticeID = nil
            session = nil
            return
        }

        currentUser = AuthenticatedUser(
            id: stored.userId,
            username: "(restoring)",
            email: "",
            displayName: nil,
            avatarUrl: nil
        )
        try? bootstrapSession(userId: stored.userId)
    }

    func handleLoginSuccess(_ response: AuthResponse) {
        currentUser = response.user
        sessionExpiredNoticeID = nil
        try? bootstrapSession(userId: response.user.id)
        session?.connectWebSocketIfNeeded()
    }

    func connectWebSocketIfNeeded() {
        session?.connectWebSocketIfNeeded()
    }

    func refreshCurrentUser() async {
        guard let stored = try? tokenStore.load() else { return }
        do {
            let user = try await makeUserRepository().fetchMe(token: stored.token)
            currentUser = user
        } catch APIError.unauthorized {
            await handleUnauthorized()
        } catch {
            // 保留占位态
        }
    }

    func logout() async {
        sessionExpiredNoticeID = nil
        await makeAuthRepository().logout()
        await tearDownSession()
    }

    /// 已保存登录态被服务端拒绝时的统一入口：清 token + 释放资源 + 回登录页。
    /// 不同点是不调 `/api/auth/logout`（token 已失效，再打也没有价值）。
    func handleUnauthorized() async {
        try? tokenStore.clear()
        await tearDownSession()
        sessionExpiredNoticeID = UUID()
    }

    /// 设计 §5.5 的三阶段清理。必须按顺序：
    /// 1. Nuke 独立清（与 SwiftData 无关）
    /// 2. 放掉 session（含 ModelContainer）+ yield 一次让 actor 排空
    /// 3. 删按 userId 的 store 目录
    func tearDownSession() async {
        let userId = session?.userId

        // 仅清内存缓存，磁盘缓存保留，以便再次登录或服务端不可用时仍能离线展示历史图片。
        ImagePipeline.shared.cache.removeAll(caches: .memory)

        session?.disconnectWebSocket(reason: .userInitiated)
        session = nil
        currentUser = nil
        await Task.yield()

        if let userId {
            let dir = URL.applicationSupportDirectory
                .appendingPathComponent("EchoIM/users/\(userId)")
            try? FileManager.default.removeItem(at: dir)
        }
    }

    /// Me 页“清除聊天缓存”按钮入口。保留 session / token，只清 SwiftData + Nuke。
    func clearChatCache() async {
        ImagePipeline.shared.cache.removeAll()
        guard let session else { return }
        try? await session.messageStore().deleteAll()
        try? await session.conversationMetaStore().deleteAll()
    }

    // MARK: - Internal

    private func bootstrapSession(userId: Int) throws {
        session = try UserSession(
            userId: userId,
            apiClient: apiClient,
            tokenLoader: { [tokenStore = self.tokenStore] in
                (try? tokenStore.load())?.token
            },
            onUnauthorized: { [weak self] in
                await self?.handleUnauthorized()
            }
        )
    }
}
