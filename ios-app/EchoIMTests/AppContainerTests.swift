import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("AppContainer", .serialized)
struct AppContainerTests {
    private func makeContainer(resetArg: Bool = false) -> (AppContainer, KeychainTokenStore) {
        let store = KeychainTokenStore(service: "com.echoim.test.\(UUID().uuidString)")
        try? store.clear()
        let container = AppContainer(
            tokenStore: store,
            apiClient: APIClient(),
            resetKeychainOnLaunch: resetArg
        )
        return (container, store)
    }

    @Test
    func bootstrapRestoresCurrentUserFromKeychain() throws {
        let (container, store) = makeContainer()
        try store.save(token: "t", userId: 42)

        container.bootstrap()

        #expect(container.currentUser?.id == 42)
        try store.clear()
    }

    @Test
    func bootstrapMarksRestoredUserAsRestoringPlaceholder() throws {
        let (container, store) = makeContainer()
        try store.save(token: "t", userId: 42)

        container.bootstrap()

        #expect(container.isRestoringCurrentUser)
        try store.clear()
    }

    @Test
    func bootstrapLeavesCurrentUserNilWhenNoToken() {
        let (container, _) = makeContainer()
        container.bootstrap()
        #expect(container.currentUser == nil)
    }

    @Test
    func logoutClearsKeychainAndCurrentUser() async throws {
        let (container, store) = makeContainer()
        try store.save(token: "t", userId: 42)
        container.bootstrap()
        #expect(container.currentUser?.id == 42)

        await container.logout()

        #expect(container.currentUser == nil)
        #expect(!container.isRestoringCurrentUser)
        #expect(try store.load() == nil)
    }

    @Test
    func handleUnauthorizedPublishesSessionExpiredNotice() async throws {
        let (container, store) = makeContainer()
        try store.save(token: "t", userId: 42)
        container.bootstrap()

        await container.handleUnauthorized()

        #expect(container.currentUser == nil)
        #expect(!container.isRestoringCurrentUser)
        #expect(try store.load() == nil)
        #expect(container.sessionExpiredNoticeID != nil)
    }

    @Test
    func tearDownSessionClearsAllUserStateAndFiles() async throws {
        let (container, store) = makeContainer()
        // 不依赖真实服务端用户；这里只验证 AppContainer 对当前 session 的本地资源清理。
        let userId = Int.random(in: 900_000_000...999_999_999)

        container.handleLoginSuccess(
            AuthResponse(
                token: "dummy",
                user: AuthenticatedUser(
                    id: userId,
                    username: "a",
                    email: "a@b.c",
                    displayName: nil,
                    avatarUrl: nil
                )
            )
        )
        // 真实登录路径由 LoginViewModel 先写 Keychain；测试里后写，避免 WS 真连本地地址。
        try store.save(token: "dummy", userId: userId)

        let sessionBefore = container.session
        #expect(sessionBefore != nil)

        let userDir = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)")
        #expect(FileManager.default.fileExists(atPath: userDir.path))

        await container.tearDownSession()

        #expect(container.session == nil)
        #expect(container.currentUser == nil)
        #expect(!container.isRestoringCurrentUser)
        #expect(!FileManager.default.fileExists(atPath: userDir.path))
        #expect(try store.load() != nil)
        try store.clear()
    }

    @Test
    func resetKeychainFlagWipesOnBootstrap() throws {
        let (container, store) = makeContainer(resetArg: true)
        try store.save(token: "t", userId: 42)

        container.bootstrap()

        #expect(container.currentUser == nil)
        #expect(!container.isRestoringCurrentUser)
        #expect(try store.load() == nil)
    }
}
