# iOS P2 实施计划：好友 / 会话列表 + 用户资料拉取

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ios-app/` 从 P1 的"登录/注册 + 占位首页"推进到"登录后进入三 Tab 主界面（聊天列表 / 联系人 / 我），能看到好友、好友申请、会话列表，能互加好友"的第二个垂直切片（对应设计文档第 8 节 P2）。

**Architecture:** 复用 P1 的 SwiftUI + MVVM + `@Observable`；引入 `UserProfile` 共享模型、四个 Repository、基于 Nuke `LazyImage` 的 `AvatarView`；主界面用 `TabView` 三分区；所有列表走 REST + `.refreshable` 下拉刷新（WebSocket 驱动的实时更新留给 P3）。

**Tech Stack:** SwiftUI、Swift Concurrency、URLSession、KeychainAccess、Nuke / NukeUI（本阶段首次使用）、Swift Testing、XCUITest。

**TDD 适用范围（与 P1 一致）：**
- **纯逻辑 → TDD**：Data model 的 Decodable（尤其 `Conversation.init(from:)` 的 peer 扁平→嵌套聚合）、Repository 方法的 endpoint / body / 响应解码、`AppContainer.refreshCurrentUser()` 的 200 / 401 / network 分支。
- **View / 集成 → 编译 + 模拟器手工清单**：`MainTabView` / `ConversationsListView` / `ContactsView` / `MeView` 不写 SwiftUI 单测。验证方式是 `$BUILD` + 模拟器按清单走一遍 + 扩展 XCUITest smoke 覆盖 Tab 切换和好友申请主路径。

**服务端契约：** 本阶段依赖的接口全部已存在，不需要服务端改动：
- `GET /api/users/me`（`server/src/routes/users.ts:11`）
- `GET /api/users/search?q=`（`server/src/routes/users.ts:89`）
- `GET /api/friends/`（`server/src/routes/friends.ts:7`）
- `GET /api/friend-requests/`（`server/src/routes/friend-requests.ts:61`，接收到的）
- `GET /api/friend-requests/sent`（`server/src/routes/friend-requests.ts:74`，发出的）
- `GET /api/friend-requests/history`（`server/src/routes/friend-requests.ts:87`）
- `POST /api/friend-requests/` body `{ recipient_id }`（`server/src/routes/friend-requests.ts:7`）
- `PUT /api/friend-requests/:id` body `{ status }`（`server/src/routes/friend-requests.ts:103`）
- `GET /api/conversations/`（`server/src/routes/conversations.ts:8`）

设计文档 §11.1 对 `GET /api/conversations/:id/messages?limit=` 的改动是 P4 才需要的，**不**在 P2 范围内。

---

## 开发环境前提

沿用 P1（不重复）。约定命令：

```bash
# 编译（Debug）
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5,arch=arm64' \
  -configuration Debug build

# 单测
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5,arch=arm64' \
  test -only-testing:EchoIMTests

# UI 测
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5,arch=arm64' \
  test -only-testing:EchoIMUITests
```

记为 `$BUILD` / `$TEST` / `$UITEST`。

**后端前提：** 本阶段联调需要后端在跑（`docker compose up` 或 `npm --prefix server run dev`），并至少有两个互为好友的测试用户（一个已登录，一个作为对端）。没有的话先用 P1 的注册流程建好、互加好友，或用 `curl` 直接 POST `/api/friend-requests` 建立。

---

## 文件结构（P2 新增 / 修改）

本阶段**不**触及的目录：`ios-app/EchoIM/Core/Storage/`（SwiftData 是 P4）、`WebSocketClient`（P3）、`upload`（P5）。

```
ios-app/EchoIM/
├── App/
│   ├── AppContainer.swift                  // MODIFY：新增 async refreshCurrentUser() + 401 清 Keychain；factory 返回 4 个 Repository
│   └── RootView.swift                      // MODIFY：已登录态改为 MainTabView，追加 .task 调 refreshCurrentUser
├── Core/
│   ├── Networking/
│   │   ├── APIClient.swift                 // MODIFY：加 GET / DELETE 便捷封装（可选，已有 request() 已够用；此处只重构扩展）
│   │   ├── Endpoints.swift                 // MODIFY：追加 Users / Friends / FriendRequests / Conversations 路径常量
│   │   └── Models/
│   │       ├── UserProfile.swift           // NEW：id + username + displayName + avatarUrl（Friend / 搜索结果 / Conversation.peer 共用）
│   │       ├── Friend.swift                // NEW：typealias Friend = UserProfile（字段集与服务端 /friends 完全一致）
│   │       ├── FriendRequest.swift         // NEW：含 status / direction / 联表的 username / displayName / avatarUrl
│   │       └── Conversation.swift          // NEW：自定义 init(from:) 把 peer_* 扁平字段聚合成 UserProfile
│   └── UI/
│       └── AvatarView.swift                // NEW：NukeUI LazyImage + 首字母 fallback
├── Features/
│   ├── Main/
│   │   ├── MainTabView.swift               // NEW：TabView (chats / contacts / me)
│   │   └── MainTab.swift                   // NEW：enum + 图标常量
│   ├── Conversations/
│   │   ├── ConversationRepository.swift    // NEW：list()
│   │   ├── ConversationsListView.swift     // NEW
│   │   └── ConversationsListViewModel.swift// NEW
│   ├── Contacts/
│   │   ├── UserRepository.swift            // NEW：fetchMe() + searchUsers()
│   │   ├── FriendRepository.swift          // NEW：list()
│   │   ├── FriendRequestRepository.swift   // NEW：incoming() / sent() / history() / send() / respond()
│   │   ├── ContactsView.swift              // NEW：NavigationStack + FriendsList + toolbar Sheet
│   │   ├── ContactsViewModel.swift         // NEW：聚合 friends / requests，下拉刷新
│   │   ├── FriendsListView.swift           // NEW：子视图
│   │   ├── FriendRequestsSheetView.swift   // NEW：接收+已发+历史
│   │   └── UserSearchSheetView.swift       // NEW：搜索 + 发送申请
│   ├── Me/
│   │   └── MeView.swift                    // NEW：展示 AvatarView + display_name + 登出；替代 HomePlaceholderView
│   └── Home/
│       └── HomePlaceholderView.swift       // DELETE（MeView 取代）

ios-app/EchoIMTests/                         // 追加文件
├── UserProfileDecodingTests.swift          // NEW：UserProfile 基础字段解码（Friend / 搜索结果共用此类型）
├── ConversationDecodingTests.swift         // NEW：peer_* 扁平→嵌套；snake_case + 可选字段
├── FriendRequestDecodingTests.swift        // NEW：incoming / sent / history（含 direction）
├── UserRepositoryTests.swift               // NEW：fetchMe 200 / 401；search URL querystring
├── FriendRepositoryTests.swift             // NEW：list 200
├── FriendRequestRepositoryTests.swift      // NEW：incoming / send / respond 三条路径
├── ConversationRepositoryTests.swift       // NEW：list 200 + 排序字段传递
├── AppContainerRefreshTests.swift          // NEW：refreshCurrentUser 200 更新；401 清 Keychain；network 保留占位
├── ConversationsListViewModelTests.swift   // NEW：load / refresh 状态机
└── ContactsViewModelTests.swift            // NEW：refresh 原子聚合；send / respond 触发刷新；无 token 短路

ios-app/EchoIMUITests/
└── TabNavigationSmokeTests.swift           // NEW：登录后看到 MainTabView，切到 Contacts 看到"联系人"标题
```

---

## Task 1：共享模型 + Endpoints 扩展

**Files:**
- Create: `ios-app/EchoIM/Core/Networking/Models/UserProfile.swift`
- Modify: `ios-app/EchoIM/Core/Networking/Endpoints.swift`
- Test: `ios-app/EchoIMTests/UserProfileDecodingTests.swift`

**动机：** Friend / 搜索结果 / Conversation.peer 三处都是 `(id, username, display_name, avatar_url)` 的元组。抽一个 `UserProfile` 共享，避免重复声明。`AuthenticatedUser` 保留（带 email），仅用于登录返回 + `GET /me`。UserRepository.searchUsers 直接返回 `[UserProfile]`，不再额外起 `SearchUser` 类型——typealias 只在语义明显加分时用，这里不加分。

- [ ] **Step 1：写失败测试**

`ios-app/EchoIMTests/UserProfileDecodingTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@Suite("UserProfile decoding")
struct UserProfileDecodingTests {
    @Test func decodesMinimalPayload() throws {
        let json = """
        { "id": 7, "username": "alice", "display_name": "Alice", "avatar_url": null }
        """.data(using: .utf8)!
        let u = try APIClient.jsonDecoder.decode(UserProfile.self, from: json)
        #expect(u.id == 7)
        #expect(u.username == "alice")
        #expect(u.displayName == "Alice")
        #expect(u.avatarUrl == nil)
    }

    @Test func missingOptionalsAreNil() throws {
        let json = """
        { "id": 8, "username": "bob" }
        """.data(using: .utf8)!
        let u = try APIClient.jsonDecoder.decode(UserProfile.self, from: json)
        #expect(u.displayName == nil)
        #expect(u.avatarUrl == nil)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：编译失败，`UserProfile` 未定义。

- [ ] **Step 3：实现 UserProfile**

`ios-app/EchoIM/Core/Networking/Models/UserProfile.swift`：

```swift
import Foundation

/// 只读用户摘要——好友、搜索结果、会话对端都复用此类型。
/// `AuthenticatedUser` 是已登录自己（带 email），与此区分。
struct UserProfile: Codable, Identifiable, Equatable, Sendable, Hashable {
    let id: Int
    let username: String
    let displayName: String?
    let avatarUrl: String?
}
```

- [ ] **Step 4：运行测试确认通过**

```bash
$TEST
```

预期：两个用例绿。

- [ ] **Step 5：扩充 Endpoints**

编辑 `ios-app/EchoIM/Core/Networking/Endpoints.swift`，在 `Auth` 之后追加：

```swift
    enum Users {
        static let me = "api/users/me"
        static let search = "api/users/search"
    }

    enum Friends {
        static let list = "api/friends"
    }

    enum FriendRequests {
        static let base = "api/friend-requests"
        static let sent = "api/friend-requests/sent"
        static let history = "api/friend-requests/history"
        static func respond(id: Int) -> String { "api/friend-requests/\(id)" }
    }

    enum Conversations {
        static let list = "api/conversations"
    }
```

- [ ] **Step 6：编译**

```bash
$BUILD
```

预期：`BUILD SUCCEEDED`。

- [ ] **Step 7：提交**

```bash
git add ios-app/EchoIM/Core/Networking/Models/UserProfile.swift \
        ios-app/EchoIM/Core/Networking/Endpoints.swift \
        ios-app/EchoIMTests/UserProfileDecodingTests.swift
git commit -m "feat(ios): add shared UserProfile model and P2 endpoint paths"
```

---

## Task 2：UserRepository（GET /me + search）

**Files:**
- Create: `ios-app/EchoIM/Features/Contacts/UserRepository.swift`
- Test: `ios-app/EchoIMTests/UserRepositoryTests.swift`

- [ ] **Step 1：写失败测试**

`ios-app/EchoIMTests/UserRepositoryTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("UserRepository")
struct UserRepositoryTests {
    @Test func fetchMeHitsCorrectEndpointAndDecodes() async throws {
        var capturedPath: String?
        var capturedAuth: String?
        let body = """
        { "id": 42, "username": "me", "email": "me@x.com",
          "display_name": "Me", "avatar_url": "/uploads/avatars/42.jpg" }
        """.data(using: .utf8)!
        let (config, _) = MockURLProtocol.configure { req in
            capturedPath = req.url?.path
            capturedAuth = req.value(forHTTPHeaderField: "Authorization")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let client = APIClient(session: URLSession(configuration: config))
        let repo = UserRepositoryImpl(api: client)

        let user = try await repo.fetchMe(token: "jwt-1")

        #expect(capturedPath == "/api/users/me")
        #expect(capturedAuth == "Bearer jwt-1")
        #expect(user.id == 42)
        #expect(user.email == "me@x.com")
        #expect(user.displayName == "Me")
    }

    @Test func fetchMeThrowsUnauthorizedOn401() async throws {
        let (config, _) = MockURLProtocol.configure { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        let client = APIClient(session: URLSession(configuration: config))
        let repo = UserRepositoryImpl(api: client)

        do {
            _ = try await repo.fetchMe(token: "stale")
            Issue.record("expected .unauthorized")
        } catch let e as APIError {
            #expect(e == .unauthorized)
        }
    }

    @Test func searchBuildsQuerystring() async throws {
        var capturedURL: URL?
        let body = "[]".data(using: .utf8)!
        let (config, _) = MockURLProtocol.configure { req in
            capturedURL = req.url
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let client = APIClient(session: URLSession(configuration: config))
        let repo = UserRepositoryImpl(api: client)

        _ = try await repo.searchUsers(query: "ali ce", token: "jwt")

        // 空格必须被 URL 编码成 %20 或 +；用 URLComponents 反解验证 query 有 q=ali ce
        let comps = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)!
        let q = comps.queryItems?.first { $0.name == "q" }?.value
        #expect(q == "ali ce")
        #expect(capturedURL?.path == "/api/users/search")
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`UserRepository*` / `UserRepositoryImpl` 未定义。

- [ ] **Step 3：实现**

`ios-app/EchoIM/Features/Contacts/UserRepository.swift`：

```swift
import Foundation

protocol UserRepository {
    func fetchMe(token: String) async throws -> AuthenticatedUser
    func searchUsers(query: String, token: String) async throws -> [UserProfile]
}

@MainActor
final class UserRepositoryImpl: UserRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func fetchMe(token: String) async throws -> AuthenticatedUser {
        try await api.request(Endpoints.Users.me, token: token)
    }

    func searchUsers(query: String, token: String) async throws -> [UserProfile] {
        var comps = URLComponents()
        comps.path = Endpoints.Users.search
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        // 只需要 path + 查询串；APIClient.request 会再拼 baseURL
        let path = comps.path + "?" + (comps.percentEncodedQuery ?? "")
        return try await api.request(path, token: token)
    }
}
```

**注意**：`APIClient.request` 当前接受的是 `path: String`，里面用 `Endpoints.url(path)` 即 `baseURL.appendingPathComponent`。`appendingPathComponent` 会对 `"api/users/search?q=alice"` 这种带问号的字符串做错误转义。需要确认：

- 如果现有实现不能透传 query string → **本 Task 追加改动**：在 `APIClient.request` 内把 path 直接喂 `URL(string:relativeTo:)`，不经 `appendingPathComponent`。

- [ ] **Step 4：APIClient 支持带 query 的 path**

编辑 `ios-app/EchoIM/Core/Networking/APIClient.swift`，把请求行替换为基于 `URL(string:relativeTo:)`：

定位 `ios-app/EchoIM/Core/Networking/APIClient.swift:71`，把：

```swift
var request = URLRequest(url: Endpoints.url(path))
```

改成：

```swift
guard let url = URL(string: path, relativeTo: Endpoints.baseURL)?.absoluteURL else {
    throw APIError.invalidResponse
}
var request = URLRequest(url: url)
```

对应 `Endpoints.swift` 同步调整 `url(_:)` 辅助（保留用于无 query 的调用位置，但内部改为 `URL(string:relativeTo:)`）：

```swift
static func url(_ path: String) -> URL {
    guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
        // path 永远是代码里的字符串常量，解析失败意味着程序员拼错路径，直接崩溃比静默出错安全
        preconditionFailure("invalid endpoint path: \(path) relative to \(baseURL)")
    }
    return url
}
```

- [ ] **Step 5：运行测试**

```bash
$TEST
```

预期：3 个 UserRepository 用例 + 原有 P1 用例全部绿。如果有 P1 测试因为 URL 构造方式变化而挂（例如 `Endpoints.url("api/auth/login")` 产出的字符串里 `baseURL` 结尾是否带斜线的差异），检查 `Endpoints.baseURL` 是否以 `/` 结尾，不够就调整 `baseURL` 的构造或直接在路径常量里加 `/` 前缀——**二选一并在测试里锁定**。

- [ ] **Step 6：提交**

```bash
git add ios-app/EchoIM/Features/Contacts/UserRepository.swift \
        ios-app/EchoIM/Core/Networking/APIClient.swift \
        ios-app/EchoIM/Core/Networking/Endpoints.swift \
        ios-app/EchoIMTests/UserRepositoryTests.swift
git commit -m "feat(ios): add UserRepository with /me and /search"
```

---

## Task 3：AppContainer async refresh + 401 → Keychain 清理

**Files:**
- Modify: `ios-app/EchoIM/App/AppContainer.swift`
- Modify: `ios-app/EchoIM/App/RootView.swift`
- Test: `ios-app/EchoIMTests/AppContainerRefreshTests.swift`

**动机：** P1 的 `bootstrap()` 只是从 Keychain 里恢复 `currentUser` 占位（username = "(restoring)"）。P2 要把占位替换成真实资料。时序策略：

- 仍保留 P1 的同步 `bootstrap()`（首帧无闪烁，依旧是 HomeView / MainTabView）
- 追加 async `refreshCurrentUser()`，RootView 在 `.task` 里调
- 200 → 用真实 `AuthenticatedUser` 覆盖占位
- 401 → `tokenStore.clear()` + `currentUser = nil`（回登录页）
- 网络错误 / 解码错误 → 保留占位（用户能看到 UI，只是 Me 标签里显示 "(restoring)"，直到下一次 refresh 成功；不强制踢出登录态）

- [ ] **Step 1：写失败测试**

`ios-app/EchoIMTests/AppContainerRefreshTests.swift`：

```swift
import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("AppContainer.refreshCurrentUser", .serialized)
struct AppContainerRefreshTests {
    private func makeSetup(
        handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> (AppContainer, KeychainTokenStore) {
        let (config, _) = MockURLProtocol.configure(handler)
        let store = KeychainTokenStore(service: "com.echoim.test.\(UUID().uuidString)")
        try? store.clear()
        let client = APIClient(session: URLSession(configuration: config))
        let container = AppContainer(tokenStore: store, apiClient: client)
        return (container, store)
    }

    @Test
    func refreshSucceedsAndReplacesPlaceholder() async throws {
        let body = """
        { "id": 9, "username": "alice", "email": "a@x.com",
          "display_name": "Alice", "avatar_url": null }
        """.data(using: .utf8)!
        let (container, store) = makeSetup { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
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
        let (container, store) = makeSetup { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        try store.save(token: "stale", userId: 9)
        container.bootstrap()
        #expect(container.currentUser != nil)

        await container.refreshCurrentUser()

        #expect(container.currentUser == nil)
        #expect(try store.load() == nil)
    }

    @Test
    func refreshKeepsPlaceholderOnNetworkError() async throws {
        let (container, store) = makeSetup { _ in
            // 任意 5xx——当前实现视 http 5xx 为非 unauthorized，保留登录态
            (HTTPURLResponse(url: URL(string: "http://x.local")!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
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
            return (HTTPURLResponse(url: URL(string: "http://x.local")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        // 没有 token：bootstrap 后 currentUser 是 nil
        container.bootstrap()
        #expect(container.currentUser == nil)

        await container.refreshCurrentUser()   // 不应该发请求

        #expect(container.currentUser == nil)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`refreshCurrentUser` 未定义，编译失败。

- [ ] **Step 3：扩充 AppContainer**

编辑 `ios-app/EchoIM/App/AppContainer.swift`，在现有实现上追加方法；最终文件（全量替换）：

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AppContainer {
    let tokenStore: KeychainTokenStore
    let apiClient: APIClient
    var currentUser: AuthenticatedUser?

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

    // MARK: - Repositories

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

    /// RootView 在 `.task` 里调用。拿到真实用户资料覆盖占位；token 失效时清 Keychain、踢回登录页。
    /// 非 401 错误保留占位——网络临时抖动不应该打断已有登录态。
    func refreshCurrentUser() async {
        guard let stored = try? tokenStore.load() else { return }

        do {
            let user = try await makeUserRepository().fetchMe(token: stored.token)
            currentUser = user
        } catch APIError.unauthorized {
            try? tokenStore.clear()
            currentUser = nil
        } catch {
            // 保留占位；下次冷启动或已登录视图重新挂载（RootView 再 task 触发）时重试。
            // App 从后台回前台的主动刷新属于 P3（设计文档 §7 的 scenePhase 联动），P2 不做。
        }
    }

    func handleLoginSuccess(_ response: AuthResponse) {
        currentUser = response.user
    }

    func logout() async {
        await makeAuthRepository().logout()
        currentUser = nil
    }
}
```

- [ ] **Step 4：RootView 接 refresh**

编辑 `ios-app/EchoIM/App/RootView.swift`，把 `.task` 加到已登录分支（本 Task 先用 HomePlaceholderView 包一层，Task 12 再整体换成 MainTabView）：

```swift
import SwiftUI

struct RootView: View {
    @State private var container: AppContainer = {
        let shouldResetKeychain = CommandLine.arguments.contains("-uitest-reset-keychain")
        let container = AppContainer(resetKeychainOnLaunch: shouldResetKeychain)
        container.bootstrap()
        return container
    }()

    @State private var showRegister = false

    var body: some View {
        Group {
            if let user = container.currentUser {
                HomePlaceholderView(user: user) {
                    await container.logout()
                    showRegister = false
                }
                .task {
                    await container.refreshCurrentUser()
                }
            } else if showRegister {
                RegisterView(vm: makeRegisterViewModel()) {
                    showRegister = false
                }
            } else {
                LoginView(vm: makeLoginViewModel()) {
                    showRegister = true
                }
            }
        }
        .animation(.default, value: container.currentUser?.id)
        .animation(.default, value: showRegister)
    }

    private func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(repo: container.makeAuthRepository()) { response in
            container.handleLoginSuccess(response)
        }
    }

    private func makeRegisterViewModel() -> RegisterViewModel {
        RegisterViewModel(repo: container.makeAuthRepository()) { response in
            container.handleLoginSuccess(response)
            showRegister = false
        }
    }
}
```

- [ ] **Step 5：运行测试**

```bash
$TEST
```

预期：4 个 refresh 用例 + P1 原有 AppContainer / 其它用例全部绿。

- [ ] **Step 6：编译**

```bash
$BUILD
```

编译过。此时 `makeUserRepository()` / `makeFriendRepository()` / `makeFriendRequestRepository()` / `makeConversationRepository()` 引用的类型还不存在——**如果编译失败**，本 Task 先只加 `makeUserRepository()`（其它 Repository 在 Task 4-6 出现后再追加 factory），保持 Task 粒度：

```swift
// 本 Task 只新增这一个 factory（其他 3 个在 Task 4/5/6 最后一 Step 追加）
func makeUserRepository() -> UserRepository {
    UserRepositoryImpl(api: apiClient)
}
```

- [ ] **Step 7：提交**

```bash
git add ios-app/EchoIM/App/AppContainer.swift \
        ios-app/EchoIM/App/RootView.swift \
        ios-app/EchoIMTests/AppContainerRefreshTests.swift
git commit -m "feat(ios): refresh current user via /me and handle token expiry on bootstrap"
```

---

## Task 4：Friend 模型 + FriendRepository

**Files:**
- Create: `ios-app/EchoIM/Core/Networking/Models/Friend.swift`
- Create: `ios-app/EchoIM/Features/Contacts/FriendRepository.swift`
- Test: `ios-app/EchoIMTests/FriendRepositoryTests.swift`
- Modify: `ios-app/EchoIM/App/AppContainer.swift`（追加 factory）

服务端返回：`[{ id, username, display_name, avatar_url }]`——与 `UserProfile` 字段完全一致。用 `typealias` 而不是新 struct，减少重复。

- [ ] **Step 1：写失败测试**

`ios-app/EchoIMTests/FriendRepositoryTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("FriendRepository")
struct FriendRepositoryTests {
    @Test func listDecodesAndHitsEndpoint() async throws {
        var capturedPath: String?
        let body = """
        [
          { "id": 1, "username": "alice", "display_name": "Alice", "avatar_url": null },
          { "id": 2, "username": "bob",   "display_name": null,    "avatar_url": "/u/2.jpg" }
        ]
        """.data(using: .utf8)!
        let (config, _) = MockURLProtocol.configure { req in
            capturedPath = req.url?.path
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let client = APIClient(session: URLSession(configuration: config))
        let repo = FriendRepositoryImpl(api: client)

        let friends = try await repo.list(token: "jwt")

        #expect(capturedPath == "/api/friends")
        #expect(friends.count == 2)
        #expect(friends[0].id == 1)
        #expect(friends[0].displayName == "Alice")
        #expect(friends[1].avatarUrl == "/u/2.jpg")
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`Friend` / `FriendRepository*` 未定义。

- [ ] **Step 3：定义 Friend（typealias）+ Repository**

`ios-app/EchoIM/Core/Networking/Models/Friend.swift`：

```swift
import Foundation

/// 服务端 /api/friends 返回字段集与 UserProfile 完全一致。
/// 用 typealias 保留领域术语，不额外声明 struct。
typealias Friend = UserProfile
```

`ios-app/EchoIM/Features/Contacts/FriendRepository.swift`：

```swift
import Foundation

protocol FriendRepository {
    func list(token: String) async throws -> [Friend]
}

@MainActor
final class FriendRepositoryImpl: FriendRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func list(token: String) async throws -> [Friend] {
        try await api.request(Endpoints.Friends.list, token: token)
    }
}
```

- [ ] **Step 4：AppContainer 追加 factory**

在 `ios-app/EchoIM/App/AppContainer.swift` 的 `makeUserRepository()` 后追加：

```swift
func makeFriendRepository() -> FriendRepository {
    FriendRepositoryImpl(api: apiClient)
}
```

- [ ] **Step 5：运行测试**

```bash
$TEST
```

预期：绿。

- [ ] **Step 6：提交**

```bash
git add ios-app/EchoIM/Core/Networking/Models/Friend.swift \
        ios-app/EchoIM/Features/Contacts/FriendRepository.swift \
        ios-app/EchoIM/App/AppContainer.swift \
        ios-app/EchoIMTests/FriendRepositoryTests.swift
git commit -m "feat(ios): add FriendRepository"
```

---

## Task 5：FriendRequest 模型 + FriendRequestRepository

**Files:**
- Create: `ios-app/EchoIM/Core/Networking/Models/FriendRequest.swift`
- Create: `ios-app/EchoIM/Features/Contacts/FriendRequestRepository.swift`
- Test: `ios-app/EchoIMTests/FriendRequestDecodingTests.swift`
- Test: `ios-app/EchoIMTests/FriendRequestRepositoryTests.swift`
- Modify: `ios-app/EchoIM/App/AppContainer.swift`

**服务端返回字段（摘自 `friend-requests.ts`）：**

- `GET /`（incoming，pending）：`id, sender_id, recipient_id, status, created_at, updated_at, username, display_name, avatar_url`——`username/display_name/avatar_url` 是 sender
- `GET /sent`：同字段集——但 `username/display_name/avatar_url` 是 recipient
- `GET /history`：额外带 `direction: 'sent' | 'received'`；`username` 等是对方（非当前用户）
- `POST /`：body `{ recipient_id }`；返回 `friend_requests` 行（无 `username` 等）
- `PUT /:id`：body `{ status: 'accepted' | 'declined' }`；返回同上

统一成一个 `FriendRequest` 结构体，所有字段可选（除 id / senderId / recipientId / status）。

- [ ] **Step 1：写解码失败测试**

`ios-app/EchoIMTests/FriendRequestDecodingTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@Suite("FriendRequest decoding")
struct FriendRequestDecodingTests {
    @Test func decodesIncomingPayload() throws {
        let json = """
        {
          "id": 10, "sender_id": 3, "recipient_id": 9, "status": "pending",
          "created_at": "2026-04-19T08:30:12.345Z",
          "updated_at": "2026-04-19T08:30:12.345Z",
          "username": "alice", "display_name": "Alice", "avatar_url": null
        }
        """.data(using: .utf8)!
        let r = try APIClient.jsonDecoder.decode(FriendRequest.self, from: json)
        #expect(r.id == 10)
        #expect(r.senderId == 3)
        #expect(r.recipientId == 9)
        #expect(r.status == .pending)
        #expect(r.username == "alice")
        #expect(r.direction == nil)
    }

    @Test func decodesHistoryWithDirection() throws {
        let json = """
        {
          "id": 11, "sender_id": 3, "recipient_id": 9, "status": "accepted",
          "created_at": "2026-04-19T08:30:12.345Z",
          "updated_at": "2026-04-19T08:31:00.000Z",
          "direction": "received",
          "username": "alice", "display_name": null, "avatar_url": null
        }
        """.data(using: .utf8)!
        let r = try APIClient.jsonDecoder.decode(FriendRequest.self, from: json)
        #expect(r.status == .accepted)
        #expect(r.direction == "received")
    }

    @Test func decodesBarePostResponseWithoutJoinedUser() throws {
        let json = """
        {
          "id": 12, "sender_id": 3, "recipient_id": 9, "status": "pending",
          "created_at": "2026-04-19T08:30:12.345Z",
          "updated_at": "2026-04-19T08:30:12.345Z"
        }
        """.data(using: .utf8)!
        let r = try APIClient.jsonDecoder.decode(FriendRequest.self, from: json)
        #expect(r.username == nil)
        #expect(r.displayName == nil)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`FriendRequest` / `FriendRequestStatus` 未定义。

- [ ] **Step 3：实现模型**

`ios-app/EchoIM/Core/Networking/Models/FriendRequest.swift`：

```swift
import Foundation

enum FriendRequestStatus: String, Codable, Equatable, Sendable {
    case pending
    case accepted
    case declined
}

struct FriendRequest: Identifiable, Equatable, Decodable, Sendable {
    let id: Int
    let senderId: Int
    let recipientId: Int
    let status: FriendRequestStatus
    let createdAt: Date
    let updatedAt: Date?
    /// /history 会返回 "sent" / "received"；incoming / sent / POST / PUT 不返回
    let direction: String?
    /// 联表的另一方的用户名——incoming 是 sender、sent 是 recipient、history 是对方。
    /// POST/PUT 响应没有这些字段，所以都是 Optional
    let username: String?
    let displayName: String?
    let avatarUrl: String?
}
```

- [ ] **Step 4：运行测试确认解码通过**

```bash
$TEST
```

预期：3 个 decoding 用例绿。

- [ ] **Step 5：写 Repository 测试**

`ios-app/EchoIMTests/FriendRequestRepositoryTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("FriendRequestRepository")
struct FriendRequestRepositoryTests {
    @Test func listIncomingHitsEndpoint() async throws {
        var capturedPath: String?
        let body = "[]".data(using: .utf8)!
        let (config, _) = MockURLProtocol.configure { req in
            capturedPath = req.url?.path
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let repo = FriendRequestRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        _ = try await repo.listIncoming(token: "jwt")
        #expect(capturedPath == "/api/friend-requests")
    }

    @Test func listSentAndHistoryHitCorrectEndpoints() async throws {
        var paths: [String] = []
        let body = "[]".data(using: .utf8)!
        let (config, _) = MockURLProtocol.configure { req in
            paths.append(req.url?.path ?? "")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let repo = FriendRequestRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        _ = try await repo.listSent(token: "jwt")
        _ = try await repo.listHistory(token: "jwt")
        #expect(paths == ["/api/friend-requests/sent", "/api/friend-requests/history"])
    }

    @Test func sendEncodesSnakeCaseRecipientId() async throws {
        var capturedBody: Data?
        var capturedMethod: String?
        let body = """
        { "id": 20, "sender_id": 1, "recipient_id": 2, "status": "pending",
          "created_at": "2026-04-19T08:30:12.345Z", "updated_at": "2026-04-19T08:30:12.345Z" }
        """.data(using: .utf8)!
        let (config, _) = MockURLProtocol.configure { req in
            capturedMethod = req.httpMethod
            // URLSession 把 httpBody 放到 httpBodyStream 里，要读流
            if let stream = req.httpBodyStream { capturedBody = Data(reading: stream) }
            else { capturedBody = req.httpBody }
            return (HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, body)
        }
        let repo = FriendRequestRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        let result = try await repo.send(recipientId: 2, token: "jwt")

        #expect(capturedMethod == "POST")
        let dict = try JSONSerialization.jsonObject(with: capturedBody ?? Data()) as? [String: Any]
        #expect(dict?["recipient_id"] as? Int == 2)
        #expect(dict?["recipientId"] == nil)  // 不得泄露 camelCase
        #expect(result.id == 20)
    }

    @Test func respondSendsStatusOnPut() async throws {
        var capturedMethod: String?
        var capturedPath: String?
        var capturedBody: Data?
        let body = """
        { "id": 20, "sender_id": 1, "recipient_id": 2, "status": "accepted",
          "created_at": "2026-04-19T08:30:12.345Z", "updated_at": "2026-04-19T08:31:00.000Z" }
        """.data(using: .utf8)!
        let (config, _) = MockURLProtocol.configure { req in
            capturedMethod = req.httpMethod
            capturedPath = req.url?.path
            if let stream = req.httpBodyStream { capturedBody = Data(reading: stream) }
            else { capturedBody = req.httpBody }
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let repo = FriendRequestRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        let result = try await repo.respond(id: 20, accept: true, token: "jwt")

        #expect(capturedMethod == "PUT")
        #expect(capturedPath == "/api/friend-requests/20")
        let dict = try JSONSerialization.jsonObject(with: capturedBody ?? Data()) as? [String: Any]
        #expect(dict?["status"] as? String == "accepted")
        #expect(result.status == .accepted)
    }
}

/// 测试辅助：把 InputStream 吸成 Data（URLSession 会把 httpBody 转成 bodyStream）
extension Data {
    init(reading input: InputStream) {
        self.init()
        input.open()
        let size = 1024
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buf.deallocate(); input.close() }
        while input.hasBytesAvailable {
            let n = input.read(buf, maxLength: size)
            if n <= 0 { break }
            self.append(buf, count: n)
        }
    }
}
```

- [ ] **Step 6：运行测试确认失败**

```bash
$TEST
```

预期：`FriendRequestRepository*` 未定义。

- [ ] **Step 7：实现 Repository**

`ios-app/EchoIM/Features/Contacts/FriendRequestRepository.swift`：

```swift
import Foundation

protocol FriendRequestRepository {
    func listIncoming(token: String) async throws -> [FriendRequest]
    func listSent(token: String) async throws -> [FriendRequest]
    func listHistory(token: String) async throws -> [FriendRequest]
    func send(recipientId: Int, token: String) async throws -> FriendRequest
    func respond(id: Int, accept: Bool, token: String) async throws -> FriendRequest
}

/// 显式 CodingKeys 把 camelCase 的 Swift 字段编成 snake_case——与 P1 APIClient 注释里
/// 说明的"需要 snake_case 时显式声明 CodingKeys"策略一致。
private struct CreateFriendRequestBody: Encodable {
    let recipientId: Int
    enum CodingKeys: String, CodingKey {
        case recipientId = "recipient_id"
    }
}

private struct RespondBody: Encodable {
    let status: String
}

@MainActor
final class FriendRequestRepositoryImpl: FriendRequestRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func listIncoming(token: String) async throws -> [FriendRequest] {
        try await api.request(Endpoints.FriendRequests.base, token: token)
    }

    func listSent(token: String) async throws -> [FriendRequest] {
        try await api.request(Endpoints.FriendRequests.sent, token: token)
    }

    func listHistory(token: String) async throws -> [FriendRequest] {
        try await api.request(Endpoints.FriendRequests.history, token: token)
    }

    func send(recipientId: Int, token: String) async throws -> FriendRequest {
        try await api.request(
            Endpoints.FriendRequests.base,
            method: "POST",
            token: token,
            body: CreateFriendRequestBody(recipientId: recipientId)
        )
    }

    func respond(id: Int, accept: Bool, token: String) async throws -> FriendRequest {
        try await api.request(
            Endpoints.FriendRequests.respond(id: id),
            method: "PUT",
            token: token,
            body: RespondBody(status: accept ? "accepted" : "declined")
        )
    }
}
```

- [ ] **Step 8：AppContainer 追加 factory**

```swift
func makeFriendRequestRepository() -> FriendRequestRepository {
    FriendRequestRepositoryImpl(api: apiClient)
}
```

- [ ] **Step 9：运行测试**

```bash
$TEST
```

预期：解码 3 + Repository 4 共 7 个用例绿。

- [ ] **Step 10：提交**

```bash
git add ios-app/EchoIM/Core/Networking/Models/FriendRequest.swift \
        ios-app/EchoIM/Features/Contacts/FriendRequestRepository.swift \
        ios-app/EchoIM/App/AppContainer.swift \
        ios-app/EchoIMTests/FriendRequestDecodingTests.swift \
        ios-app/EchoIMTests/FriendRequestRepositoryTests.swift
git commit -m "feat(ios): add FriendRequest model and repository"
```

---

## Task 6：Conversation 模型（自定义 Decodable）+ ConversationRepository

**Files:**
- Create: `ios-app/EchoIM/Core/Networking/Models/Conversation.swift`
- Create: `ios-app/EchoIM/Features/Conversations/ConversationRepository.swift`
- Test: `ios-app/EchoIMTests/ConversationDecodingTests.swift`
- Test: `ios-app/EchoIMTests/ConversationRepositoryTests.swift`
- Modify: `ios-app/EchoIM/App/AppContainer.swift`

**关键：** 服务端 `GET /api/conversations` 返回扁平 `peer_id / peer_username / peer_display_name / peer_avatar_url`，需要在 `init(from:)` 里聚合成嵌套 `peer: UserProfile`。设计文档 §4.1 给出了完整实现。

- [ ] **Step 1：写解码失败测试**

`ios-app/EchoIMTests/ConversationDecodingTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@Suite("Conversation decoding")
struct ConversationDecodingTests {
    @Test func aggregatesFlatPeerFieldsIntoUserProfile() throws {
        let json = """
        {
          "id": 5,
          "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": 9,
          "peer_username": "alice",
          "peer_display_name": "Alice A.",
          "peer_avatar_url": "/uploads/avatars/9.jpg",
          "last_message_body": "hi",
          "last_message_type": "text",
          "last_message_sender_id": 9,
          "last_message_at": "2026-04-18T13:00:00.000Z",
          "last_read_message_id": 123,
          "unread_count": 2
        }
        """.data(using: .utf8)!

        let c = try APIClient.jsonDecoder.decode(Conversation.self, from: json)
        #expect(c.id == 5)
        #expect(c.peer.id == 9)
        #expect(c.peer.username == "alice")
        #expect(c.peer.displayName == "Alice A.")
        #expect(c.peer.avatarUrl == "/uploads/avatars/9.jpg")
        #expect(c.lastMessageBody == "hi")
        #expect(c.lastMessageType == "text")
        #expect(c.lastMessageSenderId == 9)
        #expect(c.unreadCount == 2)
        #expect(c.lastReadMessageId == 123)
    }

    @Test func acceptsMinimalConversationWithoutLastMessage() throws {
        let json = """
        {
          "id": 6,
          "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": 10,
          "peer_username": "bob",
          "peer_display_name": null,
          "peer_avatar_url": null,
          "last_message_body": null,
          "last_message_type": null,
          "last_message_sender_id": null,
          "last_message_at": null,
          "last_read_message_id": null,
          "unread_count": 0
        }
        """.data(using: .utf8)!

        let c = try APIClient.jsonDecoder.decode(Conversation.self, from: json)
        #expect(c.lastMessageAt == nil)
        #expect(c.unreadCount == 0)
        #expect(c.peer.displayName == nil)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`Conversation` 未定义。

- [ ] **Step 3：实现 Conversation**

`ios-app/EchoIM/Core/Networking/Models/Conversation.swift`：

```swift
import Foundation

/// 一对一会话。服务端把 peer 用扁平字段返回（peer_id / peer_username / ...），
/// 本类型在 init(from:) 里聚合为嵌套 UserProfile，下游 VM/View 使用更方便。
/// 设计文档 §4.1 即是此结构。
struct Conversation: Identifiable, Equatable, Sendable {
    let id: Int
    let createdAt: Date
    let peer: UserProfile
    let lastMessageBody: String?
    let lastMessageType: String?
    let lastMessageSenderId: Int?
    let lastMessageAt: Date?
    let lastReadMessageId: Int?
    let unreadCount: Int
}

extension Conversation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case peerId
        case peerUsername
        case peerDisplayName
        case peerAvatarUrl
        case lastMessageBody
        case lastMessageType
        case lastMessageSenderId
        case lastMessageAt
        case lastReadMessageId
        case unreadCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        peer = UserProfile(
            id: try c.decode(Int.self, forKey: .peerId),
            username: try c.decode(String.self, forKey: .peerUsername),
            displayName: try c.decodeIfPresent(String.self, forKey: .peerDisplayName),
            avatarUrl: try c.decodeIfPresent(String.self, forKey: .peerAvatarUrl)
        )
        lastMessageBody = try c.decodeIfPresent(String.self, forKey: .lastMessageBody)
        lastMessageType = try c.decodeIfPresent(String.self, forKey: .lastMessageType)
        lastMessageSenderId = try c.decodeIfPresent(Int.self, forKey: .lastMessageSenderId)
        lastMessageAt = try c.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        lastReadMessageId = try c.decodeIfPresent(Int.self, forKey: .lastReadMessageId)
        unreadCount = try c.decode(Int.self, forKey: .unreadCount)
    }
}
```

- [ ] **Step 4：运行测试确认解码通过**

```bash
$TEST
```

预期：2 个 decoding 用例绿。

- [ ] **Step 5：Repository 测试**

`ios-app/EchoIMTests/ConversationRepositoryTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ConversationRepository")
struct ConversationRepositoryTests {
    @Test func listHitsEndpointAndDecodes() async throws {
        var capturedPath: String?
        var capturedAuth: String?
        let body = """
        [
          {
            "id": 5, "created_at": "2026-04-18T12:00:00.000Z",
            "peer_id": 9, "peer_username": "alice",
            "peer_display_name": "Alice", "peer_avatar_url": null,
            "last_message_body": "hi", "last_message_type": "text",
            "last_message_sender_id": 9,
            "last_message_at": "2026-04-18T13:00:00.000Z",
            "last_read_message_id": 100, "unread_count": 1
          }
        ]
        """.data(using: .utf8)!
        let (config, _) = MockURLProtocol.configure { req in
            capturedPath = req.url?.path
            capturedAuth = req.value(forHTTPHeaderField: "Authorization")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let repo = ConversationRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        let list = try await repo.list(token: "jwt")

        #expect(capturedPath == "/api/conversations")
        #expect(capturedAuth == "Bearer jwt")
        #expect(list.count == 1)
        #expect(list[0].peer.username == "alice")
        #expect(list[0].unreadCount == 1)
    }
}
```

- [ ] **Step 6：运行测试确认失败**

```bash
$TEST
```

预期：`ConversationRepository*` 未定义。

- [ ] **Step 7：实现**

`ios-app/EchoIM/Features/Conversations/ConversationRepository.swift`：

```swift
import Foundation

protocol ConversationRepository {
    func list(token: String) async throws -> [Conversation]
}

@MainActor
final class ConversationRepositoryImpl: ConversationRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func list(token: String) async throws -> [Conversation] {
        try await api.request(Endpoints.Conversations.list, token: token)
    }
}
```

- [ ] **Step 8：AppContainer 追加 factory**

```swift
func makeConversationRepository() -> ConversationRepository {
    ConversationRepositoryImpl(api: apiClient)
}
```

- [ ] **Step 9：运行测试**

```bash
$TEST
```

预期：全绿。

- [ ] **Step 10：提交**

```bash
git add ios-app/EchoIM/Core/Networking/Models/Conversation.swift \
        ios-app/EchoIM/Features/Conversations/ConversationRepository.swift \
        ios-app/EchoIM/App/AppContainer.swift \
        ios-app/EchoIMTests/ConversationDecodingTests.swift \
        ios-app/EchoIMTests/ConversationRepositoryTests.swift
git commit -m "feat(ios): add Conversation model and repository"
```

---

## Task 7：AvatarView（Nuke LazyImage + 首字母 fallback）

**Files:**
- Create: `ios-app/EchoIM/Core/UI/AvatarView.swift`

P1 已经通过 SPM 引入了 `Nuke` / `NukeUI`，本阶段首次使用。AvatarView 的规格：

- 输入：`UserProfile`（取 `avatarUrl` + `username` / `displayName`）+ 可选 `size`（默认 40）
- `avatarUrl == nil` 或加载失败：灰底 + 首字母（display_name 优先，否则 username），大写前两位
- 成功：圆形裁切、填充展示
- **完整 URL 处理**：服务端返回的 `avatar_url` 形如 `/uploads/avatars/9.jpg`（相对路径），需要拼 baseURL。给一个辅助 `Endpoints.absolute(_:)`。

- [ ] **Step 1：加 Endpoints.absolute(_:)**

编辑 `ios-app/EchoIM/Core/Networking/Endpoints.swift`，追加：

```swift
/// 服务端返回的 avatar / media 路径是相对根（"/uploads/..."）。
/// 相对 URL 直接拼 baseURL；已经是绝对 URL（例如测试 fixture）直接返回。
static func absolute(_ raw: String?) -> URL? {
    guard let raw, !raw.isEmpty else { return nil }
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
        return URL(string: raw)
    }
    return URL(string: raw, relativeTo: baseURL)?.absoluteURL
}
```

- [ ] **Step 2：实现 AvatarView**

`ios-app/EchoIM/Core/UI/AvatarView.swift`：

```swift
import SwiftUI
import NukeUI

struct AvatarView: View {
    let displayName: String?
    let username: String
    let avatarUrl: String?
    var size: CGFloat = 40

    init(profile: UserProfile, size: CGFloat = 40) {
        self.displayName = profile.displayName
        self.username = profile.username
        self.avatarUrl = profile.avatarUrl
        self.size = size
    }

    init(user: AuthenticatedUser, size: CGFloat = 40) {
        self.displayName = user.displayName
        self.username = user.username
        self.avatarUrl = user.avatarUrl
        self.size = size
    }

    var body: some View {
        Group {
            if let url = Endpoints.absolute(avatarUrl) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else if state.error != nil {
                        initialsPlaceholder
                    } else {
                        initialsPlaceholder.overlay(ProgressView().scaleEffect(0.6))
                    }
                }
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let base = (displayName?.isEmpty == false ? displayName! : username)
        return String(base.prefix(2)).uppercased()
    }

    private var initialsPlaceholder: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3：编译**

```bash
$BUILD
```

预期：`BUILD SUCCEEDED`，NukeUI link 通过。

- [ ] **Step 4：提交**

```bash
git add ios-app/EchoIM/Core/UI/AvatarView.swift \
        ios-app/EchoIM/Core/Networking/Endpoints.swift
git commit -m "feat(ios): add AvatarView backed by Nuke LazyImage"
```

---

## Task 8：MainTabView 脚手架

**Files:**
- Create: `ios-app/EchoIM/Features/Main/MainTab.swift`
- Create: `ios-app/EchoIM/Features/Main/MainTabView.swift`

这一步只搭壳——三个 Tab 内容先用占位 `Text`，Task 9/10/11 再填。目的是让后续 Task 能直接把成品 view 塞进对应 tab、独立 PR 粒度小。

- [ ] **Step 1：枚举 MainTab**

`ios-app/EchoIM/Features/Main/MainTab.swift`：

```swift
import Foundation

enum MainTab: Hashable, CaseIterable {
    case chats
    case contacts
    case me

    var titleKey: String {
        switch self {
        case .chats:    return "tab.chats"
        case .contacts: return "tab.contacts"
        case .me:       return "tab.me"
        }
    }

    /// SF Symbol 名称
    var systemImage: String {
        switch self {
        case .chats:    return "bubble.left.and.bubble.right"
        case .contacts: return "person.2"
        case .me:       return "person.crop.circle"
        }
    }
}
```

- [ ] **Step 2：MainTabView 脚手架**

`ios-app/EchoIM/Features/Main/MainTabView.swift`：

```swift
import SwiftUI

struct MainTabView: View {
    let container: AppContainer
    var onLogout: () async -> Void

    @State private var selection: MainTab = .chats

    var body: some View {
        TabView(selection: $selection) {
            chatsTab
                .tabItem { Label("聊天", systemImage: MainTab.chats.systemImage) }
                .tag(MainTab.chats)

            contactsTab
                .tabItem { Label("联系人", systemImage: MainTab.contacts.systemImage) }
                .tag(MainTab.contacts)

            meTab
                .tabItem { Label("我", systemImage: MainTab.me.systemImage) }
                .tag(MainTab.me)
        }
        .accessibilityIdentifier("mainTabView")
    }

    // 后续 Task 逐个替换这些占位 body
    private var chatsTab: some View {
        Text("Chats placeholder")
            .accessibilityIdentifier("tabChatsPlaceholder")
    }
    private var contactsTab: some View {
        Text("Contacts placeholder")
            .accessibilityIdentifier("tabContactsPlaceholder")
    }
    private var meTab: some View {
        Text("Me placeholder")
            .accessibilityIdentifier("tabMePlaceholder")
    }
}
```

- [ ] **Step 3：编译**

```bash
$BUILD
```

预期：`BUILD SUCCEEDED`。注意此时 RootView 还没切过来，MainTabView 只是存在但未接入。

- [ ] **Step 4：提交**

```bash
git add ios-app/EchoIM/Features/Main/
git commit -m "feat(ios): scaffold MainTabView with chats/contacts/me tabs"
```

---

## Task 9：ConversationsListView + ViewModel

**Files:**
- Create: `ios-app/EchoIM/Features/Conversations/ConversationsListViewModel.swift`
- Create: `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`
- Test: `ios-app/EchoIMTests/ConversationsListViewModelTests.swift`

VM 职责：初次加载、下拉刷新、空态 / 错误态。P2 没有 WS，所以会话列表只在 onAppear / refresh 时拉一次；P3 引入 WS 后会改成实时更新。

- [ ] **Step 1：写 ViewModel 失败测试**

`ios-app/EchoIMTests/ConversationsListViewModelTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ConversationsListViewModel")
struct ConversationsListViewModelTests {
    final class FakeRepo: ConversationRepository {
        var pendingResult: Result<[Conversation], Error>

        init(_ result: Result<[Conversation], Error>) {
            self.pendingResult = result
        }

        func list(token: String) async throws -> [Conversation] {
            try pendingResult.get()
        }
    }

    private func makeConv(id: Int, peerName: String, unread: Int = 0, ts: String = "2026-04-18T13:00:00.000Z") throws -> Conversation {
        let json = """
        {
          "id": \(id),
          "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": \(id + 100), "peer_username": "\(peerName)",
          "peer_display_name": null, "peer_avatar_url": null,
          "last_message_body": "hi", "last_message_type": "text",
          "last_message_sender_id": \(id + 100),
          "last_message_at": "\(ts)",
          "last_read_message_id": null,
          "unread_count": \(unread)
        }
        """.data(using: .utf8)!
        return try APIClient.jsonDecoder.decode(Conversation.self, from: json)
    }

    @Test
    func loadPopulatesConversations() async throws {
        let c1 = try makeConv(id: 1, peerName: "alice", unread: 1)
        let vm = ConversationsListViewModel(
            repository: FakeRepo(.success([c1])),
            tokenProvider: { "jwt" }
        )
        await vm.load()
        #expect(vm.phase == .loaded)
        #expect(vm.conversations.count == 1)
        #expect(vm.conversations[0].peer.username == "alice")
    }

    @Test
    func loadPropagatesErrorPhase() async {
        let vm = ConversationsListViewModel(
            repository: FakeRepo(.failure(APIError.invalidResponse)),
            tokenProvider: { "jwt" }
        )
        await vm.load()
        if case .error = vm.phase { return }
        Issue.record("expected .error, got \(vm.phase)")
    }

    @Test
    func refreshReplacesExisting() async throws {
        let old = try makeConv(id: 1, peerName: "old")
        let repo = FakeRepo(.success([old]))
        let vm = ConversationsListViewModel(repository: repo, tokenProvider: { "jwt" })
        await vm.load()
        #expect(vm.conversations[0].peer.username == "old")

        let new = try makeConv(id: 2, peerName: "new")
        repo.pendingResult = .success([new])
        await vm.refresh()

        #expect(vm.conversations.count == 1)
        #expect(vm.conversations[0].peer.username == "new")
    }

    @Test
    func loadNoOpWithoutToken() async {
        let repo = FakeRepo(.success([]))
        let vm = ConversationsListViewModel(repository: repo, tokenProvider: { nil })
        await vm.load()
        #expect(vm.phase == .unauthenticated)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`ConversationsListViewModel` 未定义。

- [ ] **Step 3：实现 VM**

`ios-app/EchoIM/Features/Conversations/ConversationsListViewModel.swift`：

```swift
import Foundation
import Observation

enum ConversationsPhase: Equatable {
    case idle
    case loading
    case loaded
    case unauthenticated
    case error(String)
}

@Observable
@MainActor
final class ConversationsListViewModel {
    private(set) var conversations: [Conversation] = []
    private(set) var phase: ConversationsPhase = .idle

    private let repository: ConversationRepository
    private let tokenProvider: () -> String?

    init(repository: ConversationRepository, tokenProvider: @escaping () -> String?) {
        self.repository = repository
        self.tokenProvider = tokenProvider
    }

    func load() async {
        if phase == .loading { return }
        guard let token = tokenProvider() else {
            phase = .unauthenticated
            return
        }
        phase = .loading
        do {
            conversations = try await repository.list(token: token)
            phase = .loaded
        } catch {
            phase = .error(String(describing: error))
        }
    }

    func refresh() async {
        guard let token = tokenProvider() else {
            phase = .unauthenticated
            return
        }
        do {
            conversations = try await repository.list(token: token)
            phase = .loaded
        } catch {
            phase = .error(String(describing: error))
        }
    }
}
```

- [ ] **Step 4：实现 View**

`ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`：

```swift
import SwiftUI

struct ConversationsListView: View {
    @State private var vm: ConversationsListViewModel

    /// 显式 init + `State(wrappedValue:)` 明确语义：VM 只在 view 首次挂载时构造一次。
    /// MainTabView.body 因为 container 变化（例如 currentUser 从占位变成真实值）而重算时，
    /// TabView 的 child view 会被重新 init——但 `@State` 初始值只在首次生效，已构造的 VM 会被保留，
    /// 避免"切 tab / currentUser 刷新"时 VM 被重建、列表状态丢失、接口被重复打。
    init(
        repository: ConversationRepository,
        tokenProvider: @escaping () -> String?
    ) {
        _vm = State(wrappedValue: ConversationsListViewModel(
            repository: repository,
            tokenProvider: tokenProvider
        ))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("聊天")
                .refreshable { await vm.refresh() }
                .task { await vm.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .idle, .loading where vm.conversations.isEmpty:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded where vm.conversations.isEmpty:
            emptyState

        case .error(let message) where vm.conversations.isEmpty:
            errorState(message)

        case .unauthenticated:
            Text("登录已过期，请重新登录")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        default:
            list
        }
    }

    private var list: some View {
        List(vm.conversations) { c in
            ConversationRow(conversation: c)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        }
        .listStyle(.plain)
        .accessibilityIdentifier("conversationsList")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("暂无会话").foregroundStyle(.secondary)
            Text("从“联系人”里选一个好友开始聊天")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("加载失败").foregroundStyle(.secondary)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Button("重试") { Task { await vm.load() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(profile: conversation.peer, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.peer.displayName ?? conversation.peer.username)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var previewText: String {
        if let body = conversation.lastMessageBody, !body.isEmpty { return body }
        if conversation.lastMessageType == "image" { return "[图片]" }
        return "暂无消息"
    }

    private var timeString: String {
        guard let t = conversation.lastMessageAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: t, relativeTo: Date())
    }
}
```

- [ ] **Step 5：把 MainTabView 的 chatsTab 占位换成真实 view**

编辑 `ios-app/EchoIM/Features/Main/MainTabView.swift`，把 `chatsTab` 替换为：

```swift
private var chatsTab: some View {
    ConversationsListView(
        repository: container.makeConversationRepository(),
        tokenProvider: { [tokenStore = container.tokenStore] in
            (try? tokenStore.load())?.token
        }
    )
}
```

**注意**：不要在这里手动 new `ConversationsListViewModel`——VM 的所有权在 `ConversationsListView.@State` 上，这里只把依赖透传给 init。即使 MainTabView.body 因为 `container.currentUser` 变化而重算，ConversationsListView 被重新 init，`_vm = State(wrappedValue: ...)` 的初始值也会被 SwiftUI 忽略，保留首次构造的 VM 实例。

- [ ] **Step 6：运行测试 + 编译**

```bash
$TEST
$BUILD
```

预期：4 个 VM 用例绿，编译通过。

- [ ] **Step 7：提交**

```bash
git add ios-app/EchoIM/Features/Conversations/ \
        ios-app/EchoIM/Features/Main/MainTabView.swift \
        ios-app/EchoIMTests/ConversationsListViewModelTests.swift
git commit -m "feat(ios): add ConversationsListView with load/refresh/empty/error states"
```

---

## Task 10：ContactsView（好友 + 申请 sheet + 搜索 sheet）

**Files:**
- Create: `ios-app/EchoIM/Features/Contacts/ContactsViewModel.swift`
- Create: `ios-app/EchoIM/Features/Contacts/ContactsView.swift`
- Create: `ios-app/EchoIM/Features/Contacts/FriendsListView.swift`
- Create: `ios-app/EchoIM/Features/Contacts/FriendRequestsSheetView.swift`
- Create: `ios-app/EchoIM/Features/Contacts/UserSearchSheetView.swift`

**UI 设计：** NavigationStack + Friends 列表做主体，toolbar 上放两个按钮：

- Leading：信封图标 + 未处理申请数 badge → 打开 `FriendRequestsSheetView`
- Trailing："+" → 打开 `UserSearchSheetView`

Sheet 关闭后刷新主列表。

- [ ] **Step 1：ContactsViewModel（聚合 friends + 待处理申请数）**

`ios-app/EchoIM/Features/Contacts/ContactsViewModel.swift`：

```swift
import Foundation
import Observation

@Observable
@MainActor
final class ContactsViewModel {
    private(set) var friends: [Friend] = []
    private(set) var incoming: [FriendRequest] = []
    private(set) var sent: [FriendRequest] = []
    private(set) var history: [FriendRequest] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let friendRepo: FriendRepository
    private let requestRepo: FriendRequestRepository
    private let tokenProvider: () -> String?

    init(
        friendRepo: FriendRepository,
        requestRepo: FriendRequestRepository,
        tokenProvider: @escaping () -> String?
    ) {
        self.friendRepo = friendRepo
        self.requestRepo = requestRepo
        self.tokenProvider = tokenProvider
    }

    var pendingIncomingCount: Int { incoming.count }

    func refresh() async {
        guard let token = tokenProvider() else { return }
        isLoading = true
        defer { isLoading = false }
        // 并发拉——互不依赖
        async let friendsTask = friendRepo.list(token: token)
        async let incomingTask = requestRepo.listIncoming(token: token)
        async let sentTask = requestRepo.listSent(token: token)
        async let historyTask = requestRepo.listHistory(token: token)
        do {
            // 四个结果先落到局部常量——**全部成功**才一次性提交到 self，避免出现"friends 是新的、
            // history 是旧的"的混合态：抛错的 try 会把后续 await 短路，但已经赋值的 self.xxx 无法回滚。
            let (f, i, s, h) = try await (friendsTask, incomingTask, sentTask, historyTask)
            self.friends = f
            self.incoming = i
            self.sent = s
            self.history = h
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
            // 并发任务里仍有未 await 的——把它们 await 掉避免 Swift 6 的 "implicit cancellation" 警告
            _ = try? await (friendsTask, incomingTask, sentTask, historyTask)
        }
    }

    func respond(requestId: Int, accept: Bool) async {
        guard let token = tokenProvider() else { return }
        do {
            _ = try await requestRepo.respond(id: requestId, accept: accept, token: token)
            await refresh()    // 最简单：回应后全刷
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func send(recipientId: Int) async -> Result<Void, Error> {
        guard let token = tokenProvider() else {
            return .failure(APIError.unauthorized)
        }
        do {
            _ = try await requestRepo.send(recipientId: recipientId, token: token)
            // 全量刷一次让 `sent` 更新
            await refresh()
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
```

- [ ] **Step 2：FriendsListView（只负责渲染，数据来自父 VM）**

`ios-app/EchoIM/Features/Contacts/FriendsListView.swift`：

```swift
import SwiftUI

struct FriendsListView: View {
    let friends: [Friend]

    var body: some View {
        if friends.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("还没有好友").foregroundStyle(.secondary)
                Text("点右上角 + 搜索用户添加好友")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("friendsEmpty")
        } else {
            List(friends) { friend in
                HStack(spacing: 12) {
                    AvatarView(profile: friend, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(friend.displayName ?? friend.username)
                            .font(.subheadline.weight(.medium))
                        if friend.displayName != nil {
                            Text("@\(friend.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .accessibilityIdentifier("friendsList")
        }
    }
}
```

- [ ] **Step 3：FriendRequestsSheetView**

`ios-app/EchoIM/Features/Contacts/FriendRequestsSheetView.swift`：

```swift
import SwiftUI

struct FriendRequestsSheetView: View {
    @Bindable var vm: ContactsViewModel
    var onClose: () -> Void

    @State private var respondingId: Int?

    var body: some View {
        NavigationStack {
            List {
                if !vm.incoming.isEmpty {
                    Section("待处理") {
                        ForEach(vm.incoming) { req in
                            incomingRow(req)
                        }
                    }
                }
                if !vm.sent.isEmpty {
                    Section("已发送") {
                        ForEach(vm.sent) { req in
                            sentRow(req)
                        }
                    }
                }
                if !vm.history.isEmpty {
                    Section("历史") {
                        ForEach(vm.history) { req in
                            historyRow(req)
                        }
                    }
                }
                if vm.incoming.isEmpty && vm.sent.isEmpty && vm.history.isEmpty {
                    Text("暂无好友申请")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("好友申请")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { onClose() }
                }
            }
            .refreshable { await vm.refresh() }
        }
    }

    private func incomingRow(_ req: FriendRequest) -> some View {
        HStack(spacing: 12) {
            avatarFor(req)
            VStack(alignment: .leading, spacing: 2) {
                Text(req.displayName ?? req.username ?? "用户\(req.senderId)")
                    .font(.subheadline.weight(.medium))
                if let u = req.username {
                    Text("@\(u)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Button("同意") {
                    respondingId = req.id
                    Task {
                        await vm.respond(requestId: req.id, accept: true)
                        respondingId = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(respondingId == req.id)

                Button("拒绝") {
                    respondingId = req.id
                    Task {
                        await vm.respond(requestId: req.id, accept: false)
                        respondingId = nil
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(respondingId == req.id)
            }
        }
    }

    private func sentRow(_ req: FriendRequest) -> some View {
        HStack(spacing: 12) {
            avatarFor(req)
            VStack(alignment: .leading, spacing: 2) {
                Text(req.displayName ?? req.username ?? "用户\(req.recipientId)")
                    .font(.subheadline.weight(.medium))
                if let u = req.username {
                    Text("@\(u)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("等待接受").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func historyRow(_ req: FriendRequest) -> some View {
        HStack(spacing: 12) {
            avatarFor(req)
            VStack(alignment: .leading, spacing: 2) {
                Text(req.displayName ?? req.username ?? "用户")
                    .font(.subheadline)
                Text(req.status == .accepted ? "已接受" : "已拒绝")
                    .font(.caption)
                    .foregroundStyle(req.status == .accepted ? .green : .red)
            }
            Spacer()
            if let dir = req.direction {
                Text(dir == "sent" ? "发送" : "收到")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func avatarFor(_ req: FriendRequest) -> some View {
        // 用 username / display_name / avatar_url 三元组构造一个临时 UserProfile 给 AvatarView
        // id 不需要，给 0 即可——AvatarView 只依赖 displayName/username/avatarUrl
        let profile = UserProfile(
            id: 0,
            username: req.username ?? "?",
            displayName: req.displayName,
            avatarUrl: req.avatarUrl
        )
        return AvatarView(profile: profile, size: 40)
    }
}
```

- [ ] **Step 4：UserSearchSheetView**

`ios-app/EchoIM/Features/Contacts/UserSearchSheetView.swift`：

```swift
import SwiftUI

struct UserSearchSheetView: View {
    @Bindable var vm: ContactsViewModel
    let userRepo: UserRepository
    let tokenProvider: () -> String?
    var onClose: () -> Void

    @State private var query: String = ""
    @State private var results: [UserProfile] = []
    @State private var isSearching = false
    @State private var sendingId: Int?
    @State private var errorToast: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                list
            }
            .navigationTitle("添加好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { onClose() }
                }
            }
            .alert(item: Binding(
                get: { errorToast.map { ErrorWrapper(message: $0) } },
                set: { errorToast = $0?.message }
            )) { w in
                Alert(title: Text("发送失败"), message: Text(w.message), dismissButton: .default(Text("好")))
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("输入用户名搜索", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: query) { _, newValue in
                    searchTask?.cancel()
                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                    if trimmed.count < 2 { results = []; return }
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        if Task.isCancelled { return }
                        await performSearch(trimmed)
                    }
                }
            if !query.isEmpty {
                Button(action: { query = ""; results = [] }) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .padding()
    }

    @ViewBuilder
    private var list: some View {
        if isSearching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
            emptyHint("至少输入两个字符")
        } else if results.isEmpty {
            emptyHint("没有匹配的用户")
        } else {
            List(results) { user in
                HStack(spacing: 12) {
                    AvatarView(profile: user, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName ?? user.username).font(.subheadline.weight(.medium))
                        if user.displayName != nil {
                            Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(buttonLabel(for: user)) {
                        sendingId = user.id
                        Task {
                            let result = await vm.send(recipientId: user.id)
                            sendingId = nil
                            if case .failure(let err) = result {
                                errorToast = String(describing: err)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isAlreadySent(user.id) || sendingId == user.id)
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
    }

    private func buttonLabel(for user: UserProfile) -> String {
        if isAlreadySent(user.id) { return "已发送" }
        if sendingId == user.id { return "…" }
        return "添加"
    }

    private func isAlreadySent(_ userId: Int) -> Bool {
        vm.sent.contains { $0.recipientId == userId }
    }

    private func emptyHint(_ text: String) -> some View {
        VStack {
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func performSearch(_ trimmed: String) async {
        guard let token = tokenProvider() else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await userRepo.searchUsers(query: trimmed, token: token)
        } catch {
            results = []
        }
    }

    private struct ErrorWrapper: Identifiable {
        let message: String
        var id: String { message }
    }
}
```

- [ ] **Step 5：ContactsView 装配**

`ios-app/EchoIM/Features/Contacts/ContactsView.swift`：

```swift
import SwiftUI

struct ContactsView: View {
    @State private var vm: ContactsViewModel
    private let userRepo: UserRepository
    private let tokenProvider: () -> String?

    @State private var showRequests = false
    @State private var showSearch = false

    /// 与 ConversationsListView 同款所有权策略：VM 构造进 `@State` 的 initial value，
    /// MainTabView.body 重算导致 ContactsView 被重新 init 时，SwiftUI 会忽略这次 wrappedValue，
    /// 保留首次创建的 VM——避免切 tab / currentUser refresh 引起的 VM 重建 + 四接口重复请求。
    init(
        friendRepo: FriendRepository,
        requestRepo: FriendRequestRepository,
        userRepo: UserRepository,
        tokenProvider: @escaping () -> String?
    ) {
        _vm = State(wrappedValue: ContactsViewModel(
            friendRepo: friendRepo,
            requestRepo: requestRepo,
            tokenProvider: tokenProvider
        ))
        self.userRepo = userRepo
        self.tokenProvider = tokenProvider
    }

    var body: some View {
        NavigationStack {
            FriendsListView(friends: vm.friends)
                .navigationTitle("联系人")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showRequests = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "envelope")
                                if vm.pendingIncomingCount > 0 {
                                    Text("\(vm.pendingIncomingCount)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.red, in: Capsule())
                                        .offset(x: 10, y: -6)
                                }
                            }
                        }
                        .accessibilityIdentifier("openFriendRequests")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSearch = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("openUserSearch")
                    }
                }
                .task { await vm.refresh() }
                .refreshable { await vm.refresh() }
                .sheet(isPresented: $showRequests) {
                    FriendRequestsSheetView(vm: vm) {
                        showRequests = false
                    }
                }
                .sheet(isPresented: $showSearch) {
                    UserSearchSheetView(
                        vm: vm,
                        userRepo: userRepo,
                        tokenProvider: tokenProvider
                    ) {
                        showSearch = false
                    }
                }
        }
    }
}
```

- [ ] **Step 6：MainTabView 接入 Contacts**

编辑 `ios-app/EchoIM/Features/Main/MainTabView.swift`，把 `contactsTab` 替换为：

```swift
private var contactsTab: some View {
    ContactsView(
        friendRepo: container.makeFriendRepository(),
        requestRepo: container.makeFriendRequestRepository(),
        userRepo: container.makeUserRepository(),
        tokenProvider: { [tokenStore = container.tokenStore] in
            (try? tokenStore.load())?.token
        }
    )
}
```

**注意**：
- VM 的构造在 `ContactsView.init` 里完成并存进 `_vm = State(...)`。MainTabView 这里只传依赖——若手动 new VM 并传 `vm:`，等于把 VM 所有权放到 MainTabView，每次 body 重算都会新建 VM，踩 Codex review 指出的生命周期坑。
- `tokenProvider` 闭包里同步读 Keychain：`tokenStore` 是 `let` + Keychain，读操作不走 main actor heavy work，直接同步读即可。

- [ ] **Step 7：ContactsViewModel 单测**

`ContactsViewModel` 做了并发聚合 + send/respond 后整表刷新 + 错误分支，不再是纯展示层，值得锁住三条主路径。P3 接 WS 时这里只会变得更复杂——先打底。

`ios-app/EchoIMTests/ContactsViewModelTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ContactsViewModel")
struct ContactsViewModelTests {
    /// 手写 fake，逐次返回预设结果；每个方法独立计数，方便断言"refresh 后整表刷一次"。
    final class FakeFriendRepo: FriendRepository {
        var result: Result<[Friend], Error> = .success([])
        private(set) var callCount = 0
        func list(token: String) async throws -> [Friend] {
            callCount += 1
            return try result.get()
        }
    }
    final class FakeRequestRepo: FriendRequestRepository {
        var incomingResult: Result<[FriendRequest], Error> = .success([])
        var sentResult: Result<[FriendRequest], Error> = .success([])
        var historyResult: Result<[FriendRequest], Error> = .success([])
        var sendResult: Result<FriendRequest, Error> = .failure(APIError.invalidResponse)
        var respondResult: Result<FriendRequest, Error> = .failure(APIError.invalidResponse)
        private(set) var sendCalls: [Int] = []
        private(set) var respondCalls: [(Int, Bool)] = []
        private(set) var listCallCounts = (incoming: 0, sent: 0, history: 0)
        func listIncoming(token: String) async throws -> [FriendRequest] {
            listCallCounts.incoming += 1
            return try incomingResult.get()
        }
        func listSent(token: String) async throws -> [FriendRequest] {
            listCallCounts.sent += 1
            return try sentResult.get()
        }
        func listHistory(token: String) async throws -> [FriendRequest] {
            listCallCounts.history += 1
            return try historyResult.get()
        }
        func send(recipientId: Int, token: String) async throws -> FriendRequest {
            sendCalls.append(recipientId)
            return try sendResult.get()
        }
        func respond(id: Int, accept: Bool, token: String) async throws -> FriendRequest {
            respondCalls.append((id, accept))
            return try respondResult.get()
        }
    }

    private func decodeFR(_ json: String) throws -> FriendRequest {
        try APIClient.jsonDecoder.decode(FriendRequest.self, from: json.data(using: .utf8)!)
    }

    private func makeFriend(id: Int, username: String) -> Friend {
        UserProfile(id: id, username: username, displayName: nil, avatarUrl: nil)
    }

    @Test
    func refreshAggregatesAllFourResultsOnSuccess() async throws {
        let friendRepo = FakeFriendRepo()
        friendRepo.result = .success([makeFriend(id: 1, username: "alice")])
        let reqRepo = FakeRequestRepo()
        reqRepo.incomingResult = .success([try decodeFR("""
            { "id": 10, "sender_id": 2, "recipient_id": 9, "status": "pending",
              "created_at": "2026-04-19T08:30:12.345Z", "updated_at": "2026-04-19T08:30:12.345Z",
              "username": "bob", "display_name": null, "avatar_url": null }
        """)])
        let vm = ContactsViewModel(
            friendRepo: friendRepo, requestRepo: reqRepo, tokenProvider: { "jwt" }
        )

        await vm.refresh()

        #expect(vm.friends.count == 1)
        #expect(vm.incoming.count == 1)
        #expect(vm.pendingIncomingCount == 1)
        #expect(vm.errorMessage == nil)
        #expect(friendRepo.callCount == 1)
        #expect(reqRepo.listCallCounts.incoming == 1)
        #expect(reqRepo.listCallCounts.sent == 1)
        #expect(reqRepo.listCallCounts.history == 1)
    }

    @Test
    func refreshPartialFailureLeavesStateUntouched() async throws {
        // 先灌一次成功的状态作为 baseline
        let friendRepo = FakeFriendRepo()
        friendRepo.result = .success([makeFriend(id: 1, username: "alice")])
        let reqRepo = FakeRequestRepo()
        let vm = ContactsViewModel(
            friendRepo: friendRepo, requestRepo: reqRepo, tokenProvider: { "jwt" }
        )
        await vm.refresh()
        #expect(vm.friends.count == 1)

        // 现在让 history 挂掉，其它成功——不应该出现"friends 已刷新、history 仍保留旧值但部分已改"的混合态
        friendRepo.result = .success([
            makeFriend(id: 1, username: "alice"),
            makeFriend(id: 2, username: "bob"),
        ])
        reqRepo.historyResult = .failure(APIError.invalidResponse)

        await vm.refresh()

        // 关键断言：friends 没有被"先更新后回滚"，而是干脆没动（因为 refresh 整体失败）
        #expect(vm.friends.count == 1)       // 保持 baseline，不是 2
        #expect(vm.errorMessage != nil)
    }

    @Test
    func sendPostsRequestAndRefreshes() async throws {
        let friendRepo = FakeFriendRepo()
        let reqRepo = FakeRequestRepo()
        reqRepo.sendResult = .success(try decodeFR("""
            { "id": 20, "sender_id": 9, "recipient_id": 2, "status": "pending",
              "created_at": "2026-04-19T08:30:12.345Z", "updated_at": "2026-04-19T08:30:12.345Z" }
        """))
        let vm = ContactsViewModel(
            friendRepo: friendRepo, requestRepo: reqRepo, tokenProvider: { "jwt" }
        )

        let result = await vm.send(recipientId: 2)

        if case .failure(let err) = result {
            Issue.record("expected .success, got \(err)")
        }
        #expect(reqRepo.sendCalls == [2])
        // send 成功后要触发一次 refresh——通过 list call 计数验证
        #expect(reqRepo.listCallCounts.sent == 1)
    }

    @Test
    func sendSurfacesErrorOnFailure() async {
        let reqRepo = FakeRequestRepo()
        reqRepo.sendResult = .failure(APIError.http(status: 409, body: Data()))
        let vm = ContactsViewModel(
            friendRepo: FakeFriendRepo(), requestRepo: reqRepo, tokenProvider: { "jwt" }
        )
        let result = await vm.send(recipientId: 3)
        if case .success = result { Issue.record("expected failure") }
        // 失败时不应该走 refresh
        #expect(reqRepo.listCallCounts.sent == 0)
    }

    @Test
    func respondCallsPutAndRefreshes() async throws {
        let reqRepo = FakeRequestRepo()
        reqRepo.respondResult = .success(try decodeFR("""
            { "id": 10, "sender_id": 2, "recipient_id": 9, "status": "accepted",
              "created_at": "2026-04-19T08:30:12.345Z", "updated_at": "2026-04-19T08:31:00.000Z" }
        """))
        let vm = ContactsViewModel(
            friendRepo: FakeFriendRepo(), requestRepo: reqRepo, tokenProvider: { "jwt" }
        )

        await vm.respond(requestId: 10, accept: true)

        #expect(reqRepo.respondCalls.count == 1)
        #expect(reqRepo.respondCalls[0].0 == 10)
        #expect(reqRepo.respondCalls[0].1 == true)
        // respond 成功后要刷一次（通过 incoming 计数验证）
        #expect(reqRepo.listCallCounts.incoming == 1)
    }

    @Test
    func refreshNoOpWithoutToken() async {
        let friendRepo = FakeFriendRepo()
        let reqRepo = FakeRequestRepo()
        let vm = ContactsViewModel(
            friendRepo: friendRepo, requestRepo: reqRepo, tokenProvider: { nil }
        )
        await vm.refresh()
        #expect(friendRepo.callCount == 0)
        #expect(reqRepo.listCallCounts.incoming == 0)
    }
}
```

运行：

```bash
$TEST
```

预期：6 个 ContactsViewModel 用例全绿。

- [ ] **Step 8：编译**

```bash
$BUILD
```

预期：`BUILD SUCCEEDED`。

- [ ] **Step 9：提交**

```bash
git add ios-app/EchoIM/Features/Contacts/ \
        ios-app/EchoIM/Features/Main/MainTabView.swift \
        ios-app/EchoIMTests/ContactsViewModelTests.swift
git commit -m "feat(ios): add Contacts tab with friends list, requests sheet, and user search"
```

---

## Task 11：MeView（替代 HomePlaceholderView）

**Files:**
- Create: `ios-app/EchoIM/Features/Me/MeView.swift`
- Delete: `ios-app/EchoIM/Features/Home/HomePlaceholderView.swift`

MeView 的 P2 版本是**只读**卡片：大头像、display_name、@username、email、登出按钮。P7 会加编辑能力。

- [ ] **Step 1：实现 MeView**

`ios-app/EchoIM/Features/Me/MeView.swift`：

```swift
import SwiftUI

struct MeView: View {
    let container: AppContainer
    var onLogout: () async -> Void

    var body: some View {
        NavigationStack {
            if let user = container.currentUser {
                Form {
                    Section {
                        HStack(spacing: 16) {
                            AvatarView(user: user, size: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName ?? user.username)
                                    .font(.title3.weight(.semibold))
                                    .accessibilityIdentifier("homeUsername")
                                if user.displayName != nil {
                                    Text("@\(user.username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if !user.email.isEmpty {
                                    Text(user.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        Button(role: .destructive) {
                            Task { await onLogout() }
                        } label: {
                            HStack {
                                Spacer()
                                Text("登出")
                                Spacer()
                            }
                        }
                        .accessibilityIdentifier("homeLogout")
                    }
                }
                .navigationTitle("我")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
```

**注意：** `accessibilityIdentifier("homeUsername")` / `"homeLogout"` 与 P1 的 `HomePlaceholderView` 保持一致。Task 12 接入 `MainTabView` 后，`LoginSmokeTests` 仍会复用这两个锚点，只是需要先切到“我”tab（见 Task 13）。

- [ ] **Step 2：删除 HomePlaceholderView**

```bash
git rm ios-app/EchoIM/Features/Home/HomePlaceholderView.swift
```

同时删除空目录 `ios-app/EchoIM/Features/Home/`（`git rm` 后自动空，但 Xcode 可能有 group 引用——工程文件会在 Task 12 的 RootView 改动时被 Xcode 自动刷新，或手动在 Xcode 里 delete group）。

- [ ] **Step 3：MainTabView 接入 MeView**

编辑 `MainTabView.swift`，`meTab` 改为：

```swift
private var meTab: some View {
    MeView(container: container, onLogout: onLogout)
}
```

- [ ] **Step 4：编译**

```bash
$BUILD
```

会有 error：`HomePlaceholderView` 在 `RootView.swift` 仍被引用。不要急着修——Task 12 专门处理 RootView 切换。

**临时解法**：为了让 Task 11 独立能编译通过，在 RootView 里把 `HomePlaceholderView` 调用临时替换成 `MeView`：

```swift
// RootView 已登录分支临时替换（Task 12 会再整体改）
if let user = container.currentUser {
    MeView(container: container) {
        await container.logout()
        showRegister = false
    }
    .task { await container.refreshCurrentUser() }
}
```

（`user` 参数不再需要，因为 MeView 直接读 `container.currentUser`；可以用 `_ = user` 或直接改条件判断。更干净写法见 Task 12。）

- [ ] **Step 5：再次 `$BUILD`**

```bash
$BUILD
```

预期：`BUILD SUCCEEDED`。

- [ ] **Step 6：提交**

```bash
git add ios-app/EchoIM/Features/Me/MeView.swift \
        ios-app/EchoIM/Features/Main/MainTabView.swift \
        ios-app/EchoIM/App/RootView.swift
git rm ios-app/EchoIM/Features/Home/HomePlaceholderView.swift
git commit -m "feat(ios): replace HomePlaceholderView with MeView"
```

---

## Task 12：RootView 接 MainTabView + 模拟器清单

**Files:**
- Modify: `ios-app/EchoIM/App/RootView.swift`

把 Task 3 留下的"已登录时直接 MeView"再升级成 MainTabView。这是 P2 的最后装配步骤。

- [ ] **Step 1：RootView 改造**

全量替换 `ios-app/EchoIM/App/RootView.swift`：

```swift
import SwiftUI

struct RootView: View {
    @State private var container: AppContainer = {
        let shouldResetKeychain = CommandLine.arguments.contains("-uitest-reset-keychain")
        let container = AppContainer(resetKeychainOnLaunch: shouldResetKeychain)
        // 与 P1 保持一致：首帧同步恢复登录占位，无闪烁。
        container.bootstrap()
        return container
    }()

    @State private var showRegister = false

    var body: some View {
        Group {
            if container.currentUser != nil {
                MainTabView(container: container) {
                    await container.logout()
                    showRegister = false
                }
                .task {
                    await container.refreshCurrentUser()
                }
            } else if showRegister {
                RegisterView(vm: makeRegisterViewModel()) {
                    showRegister = false
                }
            } else {
                LoginView(vm: makeLoginViewModel()) {
                    showRegister = true
                }
            }
        }
        .animation(.default, value: container.currentUser?.id)
        .animation(.default, value: showRegister)
    }

    private func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(repo: container.makeAuthRepository()) { response in
            container.handleLoginSuccess(response)
        }
    }

    private func makeRegisterViewModel() -> RegisterViewModel {
        RegisterViewModel(repo: container.makeAuthRepository()) { response in
            container.handleLoginSuccess(response)
            showRegister = false
        }
    }
}
```

- [ ] **Step 2：编译 + 单测**

```bash
$BUILD
$TEST
```

预期：全绿。

- [ ] **Step 3：模拟器手工清单**

后端在跑、至少 2 个测试账号互为好友（账号 A / B）且 B 已经给 A 发过消息（用 curl 可伪造；或 P3 之前用 `INSERT INTO messages` + `INSERT INTO conversations`）。

- [ ] 冷启动（Keychain 无 token）→ LoginView
- [ ] 注册新账号 → 进 MainTabView，默认停在"聊天"tab；此时会话列表可能为空态，显示"暂无会话"
- [ ] 切到"联系人"tab → 友好空态"还没有好友"
- [ ] 右上角 + → 搜索 sheet 弹出；输入 "<" 不搜（< 2 字符）；输入对端用户名 → 结果列表出现；点"添加" → 按钮变"已发送"
- [ ] 切换账号（登出 → 用 B 账号登入）→ 在联系人里看到信封 badge = 1；点信封 → 待处理一条申请 → 点"同意" → 同意后主列表出现一个好友
- [ ] 此时 A 账号登入 → 联系人里也能看到 B 好友（好友数 1）
- [ ] 预置一条 A↔B 的消息（或手动 SQL 插）→ "聊天"tab 下拉刷新 → 出现一行会话，显示对方头像 + 最新消息预览 + 时间
- [ ] unread_count > 0 时右侧出现红色数字 badge
- [ ] 切到"我"tab → 显示大头像 / display_name / @username / email / 登出按钮
- [ ] "我"tab 点"登出" → 回 LoginView
- [ ] 登录后杀 App 冷启动 → 不再闪 LoginView，直接进 MainTabView（P1 不闪的行为保持）
- [ ] 联系人 tab → 下拉刷新：spinner 一闪
- [ ] 聊天 tab → 下拉刷新：spinner 一闪，列表更新
- [ ] 把 Keychain 里的 token 手动破坏（或等 token 过期）→ **冷启动** App（杀掉后重开，让 RootView 重新挂载触发 `.task`）→ refreshCurrentUser 收到 401 → 自动切回 LoginView

> **说明**：P2 的 `.task { await container.refreshCurrentUser() }` 挂在已登录视图上，仅在该视图首次出现时触发一次，**不覆盖"App 从后台回前台"**。`scenePhase == .active` 时主动刷新 + WS 重连 + presence 重建是一整套 P3 才引入的前台恢复流程（设计文档 §7.1 / §7.5）。所以本阶段**只验证冷启动路径**，"后台→前台 token 失效踢出"放到 P3 验收。

- [ ] **Step 4：提交**

```bash
git add ios-app/EchoIM/App/RootView.swift
git commit -m "feat(ios): route authenticated state to MainTabView"
```

---

## Task 13：XCUITest 扩展——Tab 导航 smoke

**Files:**
- Modify: `ios-app/EchoIMUITests/LoginSmokeTests.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/FriendsListView.swift`
- Create: `ios-app/EchoIMUITests/TabNavigationSmokeTests.swift`

Task 12 之后，登录成功默认落在 `MainTabView` 的“聊天”tab，不再是 P1 的 Home / Me 单页。因此本 Task 先把既有 `LoginSmokeTests` 更新成“登录 → MainTabView → 切到我”，再补一条 Contacts 导航 smoke。

- [ ] **Step 1：更新 LoginSmokeTests**

`ios-app/EchoIMUITests/LoginSmokeTests.swift`：

```swift
import XCTest

final class LoginSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        let app = XCUIApplication()
        // 复用测试专用启动参数，让 smoke 跑完后把模拟器恢复回未登录态，
        // 避免后续手工验证被残留 Keychain 污染。
        app.launchArguments += ["-uitest-reset-keychain"]
        app.launch()
        app.terminate()
    }

    @MainActor
    func testLoginHappyPath() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-keychain"]
        app.launch()

        let email = app.textFields["loginEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("smoke@test.local")

        let password = app.secureTextFields["loginPassword"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("password123")

        app.buttons["loginSubmit"].tap()

        let tabView = app.otherElements["mainTabView"]
        XCTAssertTrue(tabView.waitForExistence(timeout: 10))

        let meTab = app.tabBars.buttons["我"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 3))
        meTab.tap()

        let username = app.staticTexts["homeUsername"]
        XCTAssertTrue(username.waitForExistence(timeout: 10))
    }
}
```

- [ ] **Step 2：稳定 Contacts accessibility 锚点**

为了让 XCUITest 稳定命中 SwiftUI 的空态 / 列表容器，给 `FriendsListView` 的两个根容器补 `.accessibilityElement(children: .contain)`：

```swift
if friends.isEmpty {
    VStack(spacing: 8) {
        // ...
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("friendsEmpty")
} else {
    List(friends) { friend in
        // ...
    }
    .listStyle(.plain)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("friendsList")
}
```

- [ ] **Step 3：写 TabNavigationSmokeTests**

`ios-app/EchoIMUITests/TabNavigationSmokeTests.swift`：

```swift
import XCTest

final class TabNavigationSmokeTests: XCTestCase {
    func testLandsOnMainTabAndNavigatesToContacts() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-keychain"]
        app.launch()

        // 登录
        let email = app.textFields["loginEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("smoke@test.local")
        let password = app.secureTextFields["loginPassword"]
        password.tap()
        password.typeText("password123")
        app.buttons["loginSubmit"].tap()

        // 落在 MainTabView
        let tabView = app.otherElements["mainTabView"]
        XCTAssertTrue(tabView.waitForExistence(timeout: 10))

        // 切到联系人 tab
        let contactsTab = app.tabBars.buttons["联系人"]
        XCTAssertTrue(contactsTab.waitForExistence(timeout: 3))
        contactsTab.tap()

        let searchButton = app.buttons["openUserSearch"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))

        // 要么看到好友列表，要么看到空态——两者之一必出现
        let friendsList = app.descendants(matching: .any)["friendsList"]
        let friendsEmpty = app.descendants(matching: .any)["friendsEmpty"]
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if friendsList.exists || friendsEmpty.exists { return }
            usleep(200_000)
        }
        XCTFail("Expected friendsList or friendsEmpty to appear")
    }
}
```

- [ ] **Step 4：跑 UI 测试**

后端 + `smoke@test.local / password123` 账号就绪。

```bash
$UITEST
```

预期：`LoginSmokeTests`（登录 → MainTabView → 我）+ `TabNavigationSmokeTests`（登录 → MainTabView → 联系人）两个测试都绿。如果 `accessibilityIdentifier` 对不上，先 `$BUILD` 后用 Xcode 的 Accessibility Inspector 验证 identifier。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Features/Contacts/FriendsListView.swift \
        ios-app/EchoIMUITests/LoginSmokeTests.swift \
        ios-app/EchoIMUITests/TabNavigationSmokeTests.swift
git commit -m "test(ios): add tab navigation smoke test"
```

---

## Task 14：XCUITest 扩展——好友申请跨账号 smoke

**Files:**
- Modify: `ios-app/EchoIM/Features/Contacts/UserSearchSheetView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/FriendRequestsSheetView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/FriendsListView.swift`
- Create: `ios-app/EchoIMUITests/FriendRequestCrossAccountSmokeTests.swift`

**动机：** Task 13 只证明 P2 的 MainTab 壳层和 Contacts 入口可达；但 P2 的核心业务 happy path 是“两个人真的能互加好友”。本 Task 加一条跨账号 smoke：测试进程先通过后端 API 注册一对唯一临时账号，然后在**同一台模拟器**里顺序切换登录 A / B，验证发送申请、接受申请、双方好友列表和双方申请历史。这样不依赖固定 `smoke` / `smoke2` 历史状态，第二遍跑不会因为“已经是好友”而失效。

**前提：** 后端在跑；注册接口的 `INVITE_CODES` 可用。测试默认邀请码为 `letschat`，如果本地环境不同，运行前设置 `ECHOIM_UITEST_INVITE_CODE=<code>`。如后端不在 `http://localhost:3000`，设置 `ECHOIM_UITEST_BASE_URL=<base-url>`。

- [ ] **Step 1：补好友流程 UI 测试锚点**

`UserSearchSheetView`：

```swift
TextField("用户名", text: $query)
    .accessibilityIdentifier("userSearchQuery")

HStack {
    // ...
    Button("添加") { ... }
        .accessibilityIdentifier("sendFriendRequest_\(user.username)")
}
.accessibilityIdentifier("userSearchResult_\(user.username)")
```

`FriendRequestsSheetView`：

```swift
Button("同意") { ... }
    .accessibilityIdentifier("acceptFriendRequest_\(request.username ?? "\(request.senderId)")")

Button("拒绝") { ... }
    .accessibilityIdentifier("declineFriendRequest_\(request.username ?? "\(request.senderId)")")

incomingRow
    .accessibilityIdentifier("incomingFriendRequest_\(request.username ?? "\(request.senderId)")")

sentRow
    .accessibilityIdentifier("sentFriendRequest_\(request.username ?? "\(request.recipientId)")")

historyRow
    .accessibilityIdentifier(
        "historyFriendRequest_\(request.direction ?? "unknown")_\(request.username ?? "user")_\(request.status.rawValue)"
    )
```

`FriendsListView`：

```swift
friendRow
    .accessibilityIdentifier("friendRow_\(friend.username)")
```

**注意：** SwiftUI `List` 有时不会稳定暴露子按钮的 accessibility id；smoke 可以用行 id 确认目标行，再点当前页面唯一的“添加”/“同意”按钮。因为本测试每次注册一对新账号，搜索结果和待处理申请都只有目标对象。

- [ ] **Step 2：写 FriendRequestCrossAccountSmokeTests**

`ios-app/EchoIMUITests/FriendRequestCrossAccountSmokeTests.swift` 的核心结构：

```swift
@MainActor
func testCrossAccountFriendRequestFlow() async throws {
    let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8)
    let sender = TestUser(
        username: "uismokea\(suffix)",
        email: "uismokea\(suffix)@test.local",
        password: "password123"
    )
    let receiver = TestUser(
        username: "uismokeb\(suffix)",
        email: "uismokeb\(suffix)@test.local",
        password: "password123"
    )

    try await register(sender)
    try await register(receiver)

    launchFresh()
    try login(email: sender.email, password: sender.password)
    try openContacts()
    try sendFriendRequest(toUsername: receiver.username)
    try assertSentRequest(to: receiver.username)

    launchFresh()
    try login(email: receiver.email, password: receiver.password)
    try openContacts()
    try acceptIncomingFriendRequest(fromUsername: sender.username)
    try assertFriendVisible(sender.username)

    launchFresh()
    try login(email: sender.email, password: sender.password)
    try openContacts()
    try assertFriendVisible(receiver.username)
    try assertAcceptedSentHistory(to: receiver.username)
}
```

注册辅助通过真实后端 API 建账号，测试只把 UI 操作聚焦在好友流程：

```swift
private func register(_ user: TestUser) async throws {
    var request = URLRequest(url: registerURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
        RegisterRequest(
            username: user.username,
            email: user.email,
            password: user.password,
            inviteCode: inviteCode
        )
    )

    let (_, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 201 else {
        throw BootstrapError(message: "UI smoke 注册临时账号失败")
    }
}
```

覆盖点：

- [ ] A 搜索 B 并发送好友申请
- [ ] A 的已发送申请列表出现 B
- [ ] B 的收到申请列表出现 A
- [ ] B 同意后，历史记录显示 `received + accepted`
- [ ] B 好友列表出现 A
- [ ] A 重新登录后，好友列表出现 B
- [ ] A 历史记录显示 `sent + accepted`

- [ ] **Step 3：跑 targeted UI smoke**

```bash
xcodebuild -project ios-app/EchoIM.xcodeproj -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5,arch=arm64' \
  test -only-testing:EchoIMUITests/FriendRequestCrossAccountSmokeTests/testCrossAccountFriendRequestFlow
```

预期：1 条测试绿。若注册返回 403，确认 `INVITE_CODES` 与 `ECHOIM_UITEST_INVITE_CODE` 一致。

- [ ] **Step 4：提交**

```bash
git add ios-app/EchoIM/Features/Contacts/UserSearchSheetView.swift \
        ios-app/EchoIM/Features/Contacts/FriendRequestsSheetView.swift \
        ios-app/EchoIM/Features/Contacts/FriendsListView.swift \
        ios-app/EchoIMUITests/FriendRequestCrossAccountSmokeTests.swift
git commit -m "test(ios): add friend request cross-account smoke"
```

---

## Task 15：P2 收尾 + README 更新

**Files:**
- Modify: `ios-app/README.md`

- [ ] **Step 1：更新 README**

两处改动（**都必须改**，不要只改 Status）：

1. 对齐测试命令里的模拟器目标。当前 README 的 `## Test` 块还是 P1 初稿时代的旧模拟器目标，与设计文档要求的 iOS 17+ 前提 + 本计划统一用的 `iPhone 15` 脱节，会误导后续执行者。

当前开发机实际可用并已验证通过的是 `iPhone 15` + `OS=17.5` + `arch=arm64`，避免 Xcode / Simulator 把未显式指定的 `OS=latest` 指向 iOS 26 而选错目标，也避免同一设备的多架构候选提示。

把 `ios-app/README.md` 的 `## Test` 块的 xcodebuild 命令改成：

```bash
xcodebuild -project EchoIM.xcodeproj -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5,arch=arm64' test
```

2. 更新 `## Status` 块为：

```markdown
## Status
- P1 done: scaffold + login/register/home.
- P2 done: main TabView (Chats / Contacts / Me), friends list, friend requests, user search, conversation list with unread badges, avatar caching via Nuke.
- P3-P8 tracked in `docs/superpowers/specs/2026-04-17-ios-app-design.md` §8.
```

- [ ] **Step 2：全量跑一轮**

```bash
$BUILD
$TEST
$UITEST
```

三项全绿。

- [ ] **Step 3：最终提交**

```bash
git add ios-app/README.md
git commit -m "docs(ios): note P2 completion in README"
```

---

## Self-Review（完成前必过）

- [ ] **P2 覆盖设计 §8**：逐项核对
  - `UserRepository` → Task 2
  - `FriendRepository` → Task 4
  - `FriendRequestRepository`（设计文档不单列，属于 Contacts 范畴）→ Task 5
  - `ConversationRepository` → Task 6
  - TabView (Chats / Contacts / Me) → Task 8 + Task 12
  - 好友列表 → Task 10 FriendsListView
  - 好友请求入口 → Task 10 FriendRequestsSheetView（+ ContactsView 的信封 toolbar 按钮）
  - 互加好友 happy path（搜索 → 发送申请 → 对方同意 → 双方好友列表 / 历史）→ Task 14
  - 会话列表（头像、display_name、last_message 预览、unread 角标）→ Task 9 ConversationRow
  - 下拉刷新 → Task 9 + Task 10 的 `.refreshable`
  - 头像用 `LazyImage` → Task 7 AvatarView（NukeUI）
- [ ] **P2 涵盖 P1 文档中预告的改动**：
  - `AppContainer.bootstrap()` 占位 → 真实 `/api/users/me` refresh：Task 3 `refreshCurrentUser()`
  - 401 清 Keychain + 保持未登录态：Task 3 测试覆盖
- [ ] **Placeholder 扫描**：
  `grep -rn -iE "tbd|todo|implement later|similar to task" docs/superpowers/plans/2026-04-20-ios-p2-contacts-conversations.md` 应为空。
- [ ] **类型一致性**：
  - `UserProfile`：id / username / displayName / avatarUrl，`Friend = typealias UserProfile`；**不**再引入 `SearchUser` 类型——`searchUsers` 直接返回 `[UserProfile]`
  - `Conversation.peer: UserProfile`
  - `FriendRequest.status: FriendRequestStatus`（.pending / .accepted / .declined）
  - `ConversationsListViewModel.phase: ConversationsPhase`
  - `ContactsViewModel.send(recipientId:) -> Result<Void, Error>`
- [ ] **VM 生命周期（Codex review 追加）**：
  - `ConversationsListView` / `ContactsView` 都用 `@State private var vm:` + 显式 `init` 里 `_vm = State(wrappedValue: ...)` 的写法持有 VM。MainTabView 的 `chatsTab` / `contactsTab` **只传依赖**（repository + tokenProvider），**不**手动 new VM——否则 MainTabView.body 重算时 VM 会被替换、列表状态丢失、4 个接口被重复打。
  - `ContactsViewModel.refresh()` 先 `async let` 四个任务 → `try await (…)` 组成元组 → 全部成功后一次性提交到 `self`；部分失败时保留旧值 + 记 `errorMessage`，不留"新旧混合态"。
  - `ContactsViewModelTests` 的 `refreshPartialFailureLeavesStateUntouched` 用例锁住上述原子性。
- [ ] **API client 契约**：
  - `POST /api/friend-requests` body 发 `recipient_id`（snake_case），由 `CreateFriendRequestBody.CodingKeys` 强制；测试 `sendEncodesSnakeCaseRecipientId` 断言 key 为 `recipient_id` 且**不**出现 `recipientId`
  - `searchUsers` 用 URLComponents 拼 query；测试 `searchBuildsQuerystring` 断言 `q` 参数值包含空格（即未被意外 percent-encoded 成别的字符）
  - 相对 `avatar_url` 通过 `Endpoints.absolute(_:)` 拼 baseURL，绝对 URL 直通
- [ ] **bootstrap 时序**：
  - `bootstrap()` 依然同步——首帧有 token 即展示 MainTabView（只是 Me tab 的用户名短暂显示 "(restoring)"）
  - RootView `.task { await refreshCurrentUser() }` 挂在已登录分支的 view 上；MainTabView 不 own 这段逻辑
  - `refreshCurrentUser` 401 路径：`tokenStore.clear()` + `currentUser = nil` → RootView body re-evaluate → 切回 LoginView
  - **只覆盖冷启动**：`.task` 仅在已登录视图首次出现时触发一次，**不**覆盖"App 从后台回前台"。`scenePhase == .active` 的刷新 + WS 重连是设计文档 §7 的 P3 工作；本阶段手工清单只验冷启动 401 踢出。
- [ ] **工作目录一致**：所有路径都用 `ios-app/EchoIM/...` 绝对于 repo root，无裸相对路径。
- [ ] **测试 import**：所有带 `Data` / `UUID` / `JSONSerialization` 的测试文件含 `import Foundation`。
- [ ] **辅助文件**：`Data(reading: InputStream)` 扩展只用于 `FriendRequestRepositoryTests`；如果其它 suite 也需要，提成独立辅助文件 `ios-app/EchoIMTests/TestURLBody.swift`（本计划未提取，避免目录膨胀——如果后续 Task 要用再抽）
- [ ] **Nuke 首次真正 import**：`AvatarView` 里 `import NukeUI`。P1 已在 SPM 引入、未 import 任何文件；本阶段落地。
- [ ] **UI smoke**：
  - `LoginSmokeTests` 在 Task 12 后已更新为：登录成功 → 断言 `mainTabView` 出现 → 切到“我”tab → 再断言 `homeUsername`
  - `TabNavigationSmokeTests`：登录成功 → 切到“联系人”tab → 断言 `openUserSearch` 出现，再等待 `friendsList` / `friendsEmpty`
  - `FriendRequestCrossAccountSmokeTests`：每次自动注册一对唯一临时账号，同一台模拟器顺序切换 A / B，覆盖发送申请、接受申请、双方好友列表、双方申请历史
  - `MeView` 保留 `homeUsername` / `homeLogout`，`FriendsListView` 对 `friendsList` / `friendsEmpty` / `friendRow_<username>` 补稳定 accessibility 锚点，保证 UI smoke 可定位

---

## 未来阶段的依赖锚点（给 P3+ 计划起草人）

**P3 会触及本阶段的文件**：
- `ConversationsListViewModel` 需要接入 WS `message.new` / `conversation.updated` 事件，届时 VM 会从"拉一次"升级成"订阅 + merge"。
- `ContactsViewModel` 需要接入 WS `friend_request.new` / `.accepted` / `.declined`，从 `.refreshable` 的被动刷新升级成"实时 + 乐观更新"。
- `AppContainer` 会拆出 `UserSession`（设计文档 §2.2），`makeXxxRepository()` 等 factory 统一搬到 `UserSession` 上；`makeAuthRepository()` 留在 AppContainer（登录态无关）。
- `ChatView` + `ChatViewModel` 进场，从 `ConversationsListView` 点进去；对应 P2 ConversationRow 要支持 `NavigationLink(value: conversation)`。
- **前台恢复路径**（P2 刻意未实现）：RootView 监听 `@Environment(\.scenePhase)`，`.background → .active` 时触发 `await container.refreshCurrentUser()` + WS 重连 + `PresenceStore.clearAll()` + 会话列表重拉（设计文档 §7.1 / §7.5）。P3 应把 Task 12 模拟器清单里那条"后台→前台 token 失效踢出"补回验收矩阵。

**P4 会触及本阶段的文件**：
- `ConversationsListViewModel` 加一个 SwiftData `ConversationMetaStore` 依赖：先读本地 meta 立刻渲染，再异步 refresh。
- `ConversationRepository` 不变（仍然直连服务端），只是 VM 的存取层多了一层。

**P7 会触及本阶段的文件**：
- `MeView` 增加编辑入口，打开 `ProfileEditView`；`UserRepository` 追加 `updateProfile(displayName:avatarUrl:)` 和 `uploadAvatar(data:)`。

**服务端契约改动**（P4 才需要，本阶段**不**改）：
- `GET /api/conversations/:id/messages` 加 `?limit=` —— 见设计文档 §11.1。
