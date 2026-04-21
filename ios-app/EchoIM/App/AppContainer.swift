import Foundation
import Observation

@MainActor
@Observable
final class AppContainer {
    let tokenStore: KeychainTokenStore
    let apiClient: APIClient
    var currentUser: AuthenticatedUser?

    /// 仅 `-uitest-reset-keychain` 等 UI 测试参数会把它设为 true；每次启动都从未登录态开始。
    private let resetKeychainOnLaunch: Bool

    /// 懒构造：只有登录后（有 token）才创建；登出时释放（见 tearDownSession）。
    /// 这样无登录态时完全不占用 URLSession / NWPathMonitor 资源。
    private(set) var wsClient: WebSocketClient?

    init(
        tokenStore: KeychainTokenStore? = nil,
        apiClient: APIClient? = nil,
        resetKeychainOnLaunch: Bool = false
    ) {
        self.tokenStore = tokenStore ?? KeychainTokenStore()
        self.apiClient = apiClient ?? APIClient()
        self.resetKeychainOnLaunch = resetKeychainOnLaunch
    }

    // MARK: - Repositories（P2/P3 既有）

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

    func makeConversationRepository() -> ConversationRepository {
        ConversationRepositoryImpl(api: apiClient)
    }

    func makeMessageRepository() -> MessageRepository {
        MessageRepositoryImpl(api: apiClient)
    }

    // MARK: - Session lifecycle

    func bootstrap() {
        if resetKeychainOnLaunch {
            try? tokenStore.clear()
            currentUser = nil
            return
        }

        guard let stored = try? tokenStore.load() else {
            currentUser = nil
            return
        }

        currentUser = AuthenticatedUser(
            id: stored.userId,
            username: "(restoring)",
            email: "",
            displayName: nil,
            avatarUrl: nil
        )
    }

    func handleLoginSuccess(_ response: AuthResponse) {
        currentUser = response.user
        ensureWSClient()
    }

    func connectWebSocketIfNeeded() {
        ensureWSClient()
    }

    func refreshCurrentUser() async {
        guard let stored = try? tokenStore.load() else { return }
        do {
            let user = try await makeUserRepository().fetchMe(token: stored.token)
            currentUser = user
        } catch APIError.unauthorized {
            try? tokenStore.clear()
            await tearDownSession()
        } catch {
            // 保留占位态
        }
    }

    func logout() async {
        await makeAuthRepository().logout()
        await tearDownSession()
    }

    /// WS 收到 upgrade 401 时回调。与 logout 行为几乎等价：清 token + 释放资源 + 回登录页。
    /// 不同点是不调 `/api/auth/logout`（token 已失效，再打也没有价值）。
    func handleUnauthorized() async {
        try? tokenStore.clear()
        await tearDownSession()
    }

    /// 设计 §2.2 的 tearDownSession（P3 精简版）：本阶段只断 WS + 清 currentUser；
    /// Nuke 与 SwiftData 的清理 P4/P5 接入各自机制时再补。
    func tearDownSession() async {
        wsClient?.disconnect(reason: .userInitiated)
        wsClient = nil
        currentUser = nil
    }

    // MARK: - Internal

    private func ensureWSClient() {
        guard wsClient == nil, (try? tokenStore.load()) != nil else { return }
        let client = WebSocketClient(
            tokenProvider: { [tokenStore = self.tokenStore] in
                (try? tokenStore.load())?.token
            },
            onUnauthorized: { [weak self] in
                Task { @MainActor in
                    await self?.handleUnauthorized()
                }
            }
        )
        wsClient = client
        client.connectIfNeeded()
    }
}
