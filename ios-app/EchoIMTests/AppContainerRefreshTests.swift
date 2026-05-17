import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("AppContainer.refreshCurrentUser", .serialized)
struct AppContainerRefreshTests {
    private struct Setup {
        let container: AppContainer
        let store: KeychainTokenStore
        let cacheBaseDirectory: URL

        func cleanup() {
            try? store.clear()
            try? FileManager.default.removeItem(at: cacheBaseDirectory)
        }
    }

    private func makeSetup(
        handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> Setup {
        let (configuration, _) = MockURLProtocol.configure(handler)
        let store = KeychainTokenStore(service: "com.echoim.test.\(UUID().uuidString)")
        let cacheBaseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoIMRefreshTests/\(UUID().uuidString)")
        let currentUserCache = CurrentUserCacheStore(baseDirectory: cacheBaseDirectory)
        try? store.clear()
        let client = APIClient(session: URLSession(configuration: configuration))
        let container = AppContainer(
            tokenStore: store,
            apiClient: client,
            currentUserCache: currentUserCache
        )
        return Setup(
            container: container,
            store: store,
            cacheBaseDirectory: cacheBaseDirectory
        )
    }

    @Test
    func refreshSucceedsAndReplacesPlaceholder() async throws {
        let body = """
        { "id": 9, "username": "alice", "email": "a@x.com",
          "display_name": "Alice", "avatar_url": null }
        """.data(using: .utf8)!
        let setup = makeSetup { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                body
            )
        }
        defer { setup.cleanup() }
        let container = setup.container
        let store = setup.store
        try store.save(token: "good", userId: 9)
        container.bootstrap()
        #expect(container.currentUser?.username == "(restoring)")

        await container.refreshCurrentUser()

        #expect(container.currentUser?.username == "alice")
        #expect(container.currentUser?.email == "a@x.com")
        #expect(!container.isRestoringCurrentUser)
    }

    @Test
    func refreshIfRestoringSkipsAlreadyLoadedUser() async throws {
        var requestCount = 0
        let setup = makeSetup { request in
            requestCount += 1
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        defer { setup.cleanup() }
        let container = setup.container
        let store = setup.store
        try store.save(token: "good", userId: 9)
        container.handleLoginSuccess(
            AuthResponse(
                token: "good",
                user: AuthenticatedUser(
                    id: 9,
                    username: "alice",
                    email: "a@x.com",
                    displayName: nil,
                    avatarUrl: nil
                )
            )
        )

        await container.refreshCurrentUserIfRestoring()

        #expect(requestCount == 0)
        #expect(container.currentUser?.username == "alice")
    }

    @Test
    func refreshClearsKeychainOn401() async throws {
        let setup = makeSetup { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        defer { setup.cleanup() }
        let container = setup.container
        let store = setup.store
        try store.save(token: "stale", userId: 9)
        container.bootstrap()
        #expect(container.currentUser != nil)

        await container.refreshCurrentUser()

        #expect(container.currentUser == nil)
        #expect(try store.load() == nil)
        #expect(container.sessionExpiredNoticeID != nil)
    }

    @Test
    func refreshKeepsPlaceholderOnNetworkError() async throws {
        let setup = makeSetup { _ in
            (
                HTTPURLResponse(
                    url: URL(string: "http://x.local")!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        defer { setup.cleanup() }
        let container = setup.container
        let store = setup.store
        try store.save(token: "ok", userId: 9)
        container.bootstrap()

        await container.refreshCurrentUser()

        #expect(container.currentUser?.username == "(restoring)")
        #expect(container.isRestoringCurrentUser)
        #expect(try store.load() != nil)
    }

    @Test
    func refreshIsNoOpWithoutToken() async {
        let setup = makeSetup { _ in
            Issue.record("should not be called")
            return (
                HTTPURLResponse(
                    url: URL(string: "http://x.local")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        defer { setup.cleanup() }
        let container = setup.container
        container.bootstrap()
        #expect(container.currentUser == nil)

        await container.refreshCurrentUser()

        #expect(container.currentUser == nil)
    }
}
