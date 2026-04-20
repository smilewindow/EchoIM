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
        #expect(try store.load() == nil)
    }

    @Test
    func resetKeychainFlagWipesOnBootstrap() throws {
        let (container, store) = makeContainer(resetArg: true)
        try store.save(token: "t", userId: 42)

        container.bootstrap()

        #expect(container.currentUser == nil)
        #expect(try store.load() == nil)
    }
}
