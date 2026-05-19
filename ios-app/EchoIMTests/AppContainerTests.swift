import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("AppContainer", .serialized)
struct AppContainerTests {
    private struct Setup {
        let container: AppContainer
        let store: KeychainTokenStore
        let currentUserCache: CurrentUserCacheStore
        let cacheBaseDirectory: URL

        @MainActor
        func cleanup() {
            try? store.clear()
            try? FileManager.default.removeItem(at: cacheBaseDirectory)
        }
    }

    private func makeSetup(
        resetArg: Bool = false,
        imageCacheClearer: (@MainActor () throws -> Void)? = nil
    ) -> Setup {
        let store = KeychainTokenStore(service: "com.echoim.test.\(UUID().uuidString)")
        let cacheBaseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoIMTests/\(UUID().uuidString)")
        let currentUserCache = CurrentUserCacheStore(baseDirectory: cacheBaseDirectory)
        try? store.clear()
        let container = AppContainer(
            tokenStore: store,
            apiClient: APIClient(),
            currentUserCache: currentUserCache,
            resetKeychainOnLaunch: resetArg,
            imageCacheClearer: imageCacheClearer
        )
        return Setup(
            container: container,
            store: store,
            currentUserCache: currentUserCache,
            cacheBaseDirectory: cacheBaseDirectory
        )
    }

    private func removeUserCacheDirectory(userId: Int) {
        let dir = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)")
        try? FileManager.default.removeItem(at: dir)
    }

    @Test
    func bootstrapRestoresCurrentUserFromKeychain() throws {
        let setup = makeSetup()
        defer { setup.cleanup() }
        let container = setup.container
        let store = setup.store
        try store.save(token: "t", userId: 42)

        container.bootstrap()

        #expect(container.currentUser?.id == 42)
    }

    @Test
    func bootstrapMarksRestoredUserAsRestoringPlaceholder() throws {
        let setup = makeSetup()
        defer { setup.cleanup() }
        let container = setup.container
        let store = setup.store
        try store.save(token: "t", userId: 42)

        container.bootstrap()

        #expect(container.isRestoringCurrentUser)
    }

    @Test
    func bootstrapUsesCachedCurrentUserBeforeRefresh() async throws {
        let setup = makeSetup()
        defer { setup.cleanup() }
        let firstContainer = setup.container
        let store = setup.store
        let userId = Int.random(in: 800_000_000...899_999_999)
        defer { removeUserCacheDirectory(userId: userId) }
        let cachedUser = AuthenticatedUser(
            id: userId,
            username: "alice",
            email: "alice@example.com",
            displayName: "Alice",
            avatarUrl: "/uploads/avatars/alice.jpg"
        )
        firstContainer.handleLoginSuccess(AuthResponse(token: "t", user: cachedUser))
        try store.save(token: "t", userId: userId)

        let secondContainer = AppContainer(
            tokenStore: store,
            apiClient: APIClient(),
            currentUserCache: setup.currentUserCache
        )
        secondContainer.bootstrap()

        #expect(secondContainer.currentUser == cachedUser)
        #expect(secondContainer.isRestoringCurrentUser)

        await firstContainer.tearDownSession()
        await secondContainer.tearDownSession()
    }

    @Test
    func bootstrapLeavesCurrentUserNilWhenNoToken() {
        let setup = makeSetup()
        defer { setup.cleanup() }
        let container = setup.container
        container.bootstrap()
        #expect(container.currentUser == nil)
    }

    @Test
    func logoutClearsKeychainAndCurrentUser() async throws {
        let setup = makeSetup()
        defer { setup.cleanup() }
        let container = setup.container
        let store = setup.store
        try store.save(token: "t", userId: 42)
        container.bootstrap()
        #expect(container.currentUser?.id == 42)

        await container.logout()

        #expect(container.currentUser == nil)
        #expect(!container.isRestoringCurrentUser)
        #expect(try store.load() == nil)
    }

    @Test
    func handleUnauthorizedShowsSessionExpiredToast() async throws {
        let setup = makeSetup()
        defer { setup.cleanup() }
        let container = setup.container
        let store = setup.store
        try store.save(token: "t", userId: 42)
        container.bootstrap()

        await container.handleUnauthorized()

        #expect(container.currentUser == nil)
        #expect(!container.isRestoringCurrentUser)
        #expect(try store.load() == nil)
        #expect(container.currentToast?.message == "登录状态已失效，请重新登录")
    }

    @Test
    func tearDownSessionClearsUserStateButKeepsCacheFiles() async throws {
        let setup = makeSetup()
        defer { setup.cleanup() }
        let container = setup.container
        let store = setup.store
        // 不依赖真实服务端用户；这里只验证 AppContainer 对当前 session 的本地资源清理。
        let userId = Int.random(in: 900_000_000...999_999_999)
        defer { removeUserCacheDirectory(userId: userId) }

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
        #expect(FileManager.default.fileExists(atPath: userDir.path))
        #expect(try store.load() != nil)
    }

    @Test
    func clearChatCacheDeletesMessagesAndKeepsLightweightCaches() async throws {
        let setup = makeSetup()
        defer { setup.cleanup() }
        let container = setup.container
        let userId = Int.random(in: 700_000_000...799_999_999)
        defer { removeUserCacheDirectory(userId: userId) }

        container.handleLoginSuccess(
            AuthResponse(
                token: "dummy",
                user: AuthenticatedUser(
                    id: userId,
                    username: "alice",
                    email: "a@b.c",
                    displayName: nil,
                    avatarUrl: nil
                )
            )
        )
        let session = try #require(container.session)
        let messageStore = session.messageStore()
        let metaStore = session.conversationMetaStore()
        let friendStore = session.friendCacheStore()

        try await messageStore.append([
            Message(
                id: 101,
                conversationId: 33,
                senderId: userId,
                body: "hello",
                messageType: "text",
                mediaUrl: nil,
                createdAt: Date(),
                clientTempId: nil
            ),
        ])
        try await metaStore.upsert(
            ConversationMetaSnapshot(
                conversationId: 33,
                peerUserId: 44,
                peerUsername: "bob",
                peerDisplayName: "Bob",
                peerAvatarUrl: nil,
                oldestCachedMessageId: 101,
                newestCachedMessageId: 101,
                lastReadMessageId: nil,
                unreadCount: 1,
                lastMessageBody: "hello",
                lastMessageType: "text",
                lastMessageAt: Date()
            )
        )
        try await friendStore.saveAll([
            UserProfile(id: 44, username: "bob", displayName: "Bob", avatarUrl: nil),
        ])

        try await container.clearChatCache()

        let messages = try await messageStore.loadLatest(conversationId: 33, limit: 10)
        let meta = try await metaStore.load(conversationId: 33)
        let friends = try await friendStore.loadAll()
        #expect(messages.isEmpty)
        #expect(meta?.peerUsername == "bob")
        #expect(meta?.oldestCachedMessageId == nil)
        #expect(meta?.newestCachedMessageId == nil)
        #expect(friends.map(\.username) == ["bob"])
    }

    @Test
    func clearChatCacheSurfacesFailureToCaller() async throws {
        struct CacheClearFailure: Error {}
        let setup = makeSetup(imageCacheClearer: { throw CacheClearFailure() })
        defer { setup.cleanup() }
        let container = setup.container
        let userId = Int.random(in: 600_000_000...699_999_999)
        defer { removeUserCacheDirectory(userId: userId) }

        container.handleLoginSuccess(
            AuthResponse(
                token: "dummy",
                user: AuthenticatedUser(
                    id: userId,
                    username: "alice",
                    email: "a@b.c",
                    displayName: nil,
                    avatarUrl: nil
                )
            )
        )

        await #expect(throws: CacheClearFailure.self) {
            try await container.clearChatCache()
        }
    }

    @Test
    func resetKeychainFlagWipesOnBootstrap() throws {
        let setup = makeSetup(resetArg: true)
        defer { setup.cleanup() }
        let container = setup.container
        let store = setup.store
        try store.save(token: "t", userId: 42)

        container.bootstrap()

        #expect(container.currentUser == nil)
        #expect(!container.isRestoringCurrentUser)
        #expect(try store.load() == nil)
    }
}
