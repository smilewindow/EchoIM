import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("AppContainer.refreshCurrentUser", .serialized)
struct AppContainerRefreshTests {
    private func makeSetup(
        handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> (AppContainer, KeychainTokenStore) {
        let (configuration, _) = MockURLProtocol.configure(handler)
        let store = KeychainTokenStore(service: "com.echoim.test.\(UUID().uuidString)")
        try? store.clear()
        let client = APIClient(session: URLSession(configuration: configuration))
        let container = AppContainer(tokenStore: store, apiClient: client)
        return (container, store)
    }

    @Test
    func refreshSucceedsAndReplacesPlaceholder() async throws {
        let body = """
        { "id": 9, "username": "alice", "email": "a@x.com",
          "display_name": "Alice", "avatar_url": null }
        """.data(using: .utf8)!
        let (container, store) = makeSetup { request in
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
        try store.save(token: "good", userId: 9)
        container.bootstrap()
        #expect(container.currentUser?.username == "(restoring)")

        await container.refreshCurrentUser()

        #expect(container.currentUser?.username == "alice")
        #expect(container.currentUser?.email == "a@x.com")
        try store.clear()
    }

    @Test
    func refreshClearsKeychainOn401() async throws {
        let (container, store) = makeSetup { request in
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
        let (container, store) = makeSetup { _ in
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
        try store.save(token: "ok", userId: 9)
        container.bootstrap()

        await container.refreshCurrentUser()

        #expect(container.currentUser?.username == "(restoring)")
        #expect(try store.load() != nil)
        try store.clear()
    }

    @Test
    func refreshIsNoOpWithoutToken() async {
        let (container, _) = makeSetup { _ in
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
        container.bootstrap()
        #expect(container.currentUser == nil)

        await container.refreshCurrentUser()

        #expect(container.currentUser == nil)
    }
}
