import Foundation
import Observation

@MainActor
@Observable
final class AppContainer {
    let tokenStore: KeychainTokenStore
    let apiClient: APIClient
    var currentUser: AuthenticatedUser?

    /// 仅 UI 测试传 true，让每次启动都从未登录态开始。
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

    func logout() async {
        await makeAuthRepository().logout()
        currentUser = nil
    }
}
