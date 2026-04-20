import Foundation
import Observation

@MainActor
@Observable
final class AppContainer {
    let tokenStore: KeychainTokenStore
    let apiClient: APIClient
    var currentUser: AuthenticatedUser?

    /// 仅 `-uitest-reset-keychain` 这类 UI 测试启动参数会传 true，
    /// 让每次启动都从未登录态开始，避免前一次登录态污染 smoke case。
    private let resetKeychainOnLaunch: Bool

    init(
        tokenStore: KeychainTokenStore? = nil,
        apiClient: APIClient? = nil,
        resetKeychainOnLaunch: Bool = false
    ) {
        self.tokenStore = tokenStore ?? KeychainTokenStore()
        self.apiClient = apiClient ?? APIClient()
        self.resetKeychainOnLaunch = resetKeychainOnLaunch
    }

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

    /// P1 阶段只要 Keychain 里还留着 token，就先把用户视为已登录。
    /// 真实用户资料的补全留到后续阶段通过 `/api/users/me` 拉取。
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
    }

    /// 启动后异步补全真实用户资料；只有 token 失效才回到登录页。
    /// 网络抖动或服务端临时异常都保留占位态，避免无意义地把用户踢下线。
    func refreshCurrentUser() async {
        guard let stored = try? tokenStore.load() else {
            return
        }

        do {
            let user = try await makeUserRepository().fetchMe(token: stored.token)
            currentUser = user
        } catch APIError.unauthorized {
            try? tokenStore.clear()
            currentUser = nil
        } catch {
            // 保留占位态，等待后续重新进入页面或下次启动时再刷新。
        }
    }

    func logout() async {
        await makeAuthRepository().logout()
        currentUser = nil
    }
}
