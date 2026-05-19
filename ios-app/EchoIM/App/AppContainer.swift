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
    private let toastCenter: ToastCenter
    private let currentUserCache: CurrentUserCacheStore
    private let imageCacheClearer: @MainActor () throws -> Void
    var currentUser: AuthenticatedUser?
    var isRestoringCurrentUser = false

    var currentToast: ToastMessage? {
        toastCenter.current
    }

    /// 当前登录用户的会话。未登录时 nil。P4 起 wsClient / 会话相关 repo 都从这里取。
    private(set) var session: UserSession?

    /// 仅 UI 测试参数 `-uitest-reset-keychain` 会把它设为 true。
    private let resetKeychainOnLaunch: Bool

    init(
        tokenStore: KeychainTokenStore? = nil,
        apiClient: APIClient? = nil,
        currentUserCache: CurrentUserCacheStore? = nil,
        resetKeychainOnLaunch: Bool = false,
        imageCacheClearer: (@MainActor () throws -> Void)? = nil
    ) {
        self.tokenStore = tokenStore ?? KeychainTokenStore()
        self.apiClient = apiClient ?? APIClient()
        self.toastCenter = ToastCenter()
        self.currentUserCache = currentUserCache ?? CurrentUserCacheStore()
        self.resetKeychainOnLaunch = resetKeychainOnLaunch
        self.imageCacheClearer = imageCacheClearer ?? {
            ImagePipeline.shared.cache.removeAll()
        }

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

    func showErrorToast(for error: Error) {
        toastCenter.show(error: error)
    }

    func showToast(_ message: String) {
        toastCenter.show(message)
    }

    // MARK: - Session lifecycle

    func bootstrap() {
        if resetKeychainOnLaunch {
            try? tokenStore.clear()
            currentUser = nil
            isRestoringCurrentUser = false
            session = nil
            return
        }

        guard let stored = try? tokenStore.load() else {
            currentUser = nil
            isRestoringCurrentUser = false
            session = nil
            Log.info(.app, "bootstrap no stored token")
            return
        }

        currentUser = currentUserCache.load(userId: stored.userId)
            ?? AuthenticatedUser(
                id: stored.userId,
                username: "(restoring)",
                email: "",
                displayName: nil,
                avatarUrl: nil
            )
        isRestoringCurrentUser = true
        try? bootstrapSession(userId: stored.userId)
        Log.info(.app, "bootstrap restored userId=\(stored.userId)")
    }

    func handleLoginSuccess(_ response: AuthResponse) {
        updateCurrentUser(response.user)
        isRestoringCurrentUser = false
        try? bootstrapSession(userId: response.user.id)
        session?.connectWebSocketIfNeeded()
        Log.info(.auth, "login success userId=\(response.user.id)")
    }

    func connectWebSocketIfNeeded() {
        session?.connectWebSocketIfNeeded()
    }

    func refreshCurrentUser() async {
        guard let stored = try? tokenStore.load() else { return }
        do {
            let user = try await makeUserRepository().fetchMe(token: stored.token)
            updateCurrentUser(user)
            isRestoringCurrentUser = false
        } catch APIError.unauthorized {
            await handleUnauthorized()
        } catch {
            // 保留占位态
        }
    }

    func refreshCurrentUserIfRestoring() async {
        guard isRestoringCurrentUser else { return }
        await refreshCurrentUser()
    }

    func logout() async {
        Log.info(.auth, "logout, tearing down session")
        await makeAuthRepository().logout()
        await tearDownSession()
    }

    /// 已保存登录态被服务端拒绝时的统一入口：清 token + 释放资源 + 回登录页。
    /// 不同点是不调 `/api/auth/logout`（token 已失效，再打也没有价值）。
    func handleUnauthorized() async {
        Log.warning(.auth, "unauthorized, tearing down session")
        let userId = session?.userId ?? currentUser?.id ?? (try? tokenStore.load())?.userId
        if let userId {
            currentUserCache.delete(userId: userId)
        }
        try? tokenStore.clear()
        await tearDownSession()
        showToast(String(localized: "登录状态已失效，请重新登录"))
    }

    /// 释放登录态资源。不要删除 SwiftData 用户目录：登出/401 不是“清除本机数据”，
    /// 且 SQLite 连接仍可能持有 `cache.sqlite` / WAL / SHM 文件句柄。
    func tearDownSession() async {
        // 仅清内存缓存，磁盘缓存保留，以便再次登录或服务端不可用时仍能离线展示历史图片。
        ImagePipeline.shared.cache.removeAll(caches: .memory)

        session?.disconnectWebSocket(reason: .userInitiated)
        session = nil
        currentUser = nil
        isRestoringCurrentUser = false
    }

    /// Me 页“清除聊天缓存”按钮入口。保留 session / token，只清 SwiftData + Nuke。
    func clearChatCache() async throws {
        do {
            try imageCacheClearer()
            guard let session else { return }
            try await session.clearChatCache()
            Log.info(.app, "cleared chat cache")
        } catch {
            Log.error(.cache, "clear chat cache failed: \(error)")
            throw error
        }
    }

    func updateCurrentUser(_ user: AuthenticatedUser) {
        currentUser = user
        currentUserCache.save(user)
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
