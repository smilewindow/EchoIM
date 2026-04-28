# iOS P7 实施计划：Profile 编辑 + 头像上传 + 对方资料只读页

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ios-app/` 从 P6 的"在线状态 + 输入指示"推进到"自己资料可编辑 + 看到对方只读资料卡"——对应设计文档 §8 P7 阶段。具体落地：

- Me 页新增"编辑资料"入口，进入 `ProfileEditView` 编辑 `display_name` 与头像
- 头像通过 PhotosPicker 选图，客户端 400px 方形裁剪 + JPEG 0.80（对齐服务端 `AVATAR_CONFIG`）后调 `POST /api/upload/avatar`
- `display_name` 通过 `PUT /api/users/me` 单独提交（不带 `avatar_url`）；提交成功后 `AppContainer.currentUser` 立即同步
- 头像上传成功后调 `AppContainer.refreshCurrentUser()` 拉一次 `GET /api/users/me`，与 Web `fetchMe()` 路径一致
- 聊天页顶部新增对方头像（点击后 push `UserDetailView` 只读资料卡：大头像 + displayName + @username + 在线圆点）
- `UserProfile` 作为 NavigationStack 新的目的地类型，由 `ConversationsListView` / `ContactsView` 在根处注册

**Architecture:** 四件事并行展开：

1. **iOS 数据层**：新增 `Features/Me/ProfileEditViewModel.swift`（`@Observable @MainActor`，承载编辑表单状态机）；扩展 `UserRepository`，新增 `updateProfile(displayName:token:)`；扩展 `UploadRepository`，新增 `uploadAvatar(data:token:)`。Repository 协议都加默认实现保留可扩展性，但 P7 只暴露刚好够用的方法。

2. **iOS 工具层**：新增 `Core/Utilities/AvatarImageCompressor.swift`，把任意 `UIImage` 居中裁剪成方形、缩到 400×400、白底 flatten、JPEG 0.80 编码。这层独立测试（中心裁剪坐标计算 + 白底处理是 bug-prone 的部分）。和 `ImageCompressor`（消息图 1600px）保持兄弟关系，不改后者。

3. **iOS UI 层（自己资料）**：`MeView` 在身份卡 Section 加一行"编辑资料" `NavigationLink`，目的地是 `ProfileEditView`；`ProfileEditView` 是一个 `Form`：头像区（PhotosPicker + 当前头像预览 + 上传中态）+ displayName 输入框 + 保存按钮。两条网络路径独立——头像上传 / 资料保存——分别给加载态。

4. **iOS UI 层（对方资料）**：`ChatView.principalTitle` 顶部新增 28pt 小头像放在 displayTitle 左侧（保留 P6 的圆点 + typing 文案），整个 principal 区包成 `NavigationLink(value: vm.peer)`；新增 `Features/Contacts/UserDetailView.swift`（`profile: UserProfile`，纯展示，复用 `AvatarView` + `PresenceDot`）。`ConversationsListView` 与 `ContactsView` 在自己的 NavigationStack 上同时注册 `navigationDestination(for: UserProfile.self)`，让 ChatView 内部的 NavigationLink 能 push 到 UserDetailView。

**Tech Stack:** SwiftUI（`Form` / `NavigationLink(value:)` / `navigationDestination(for:)` / `@Environment(\.dismiss)`）、PhotosPicker（与 P5 一致的输入方式，单选 `.images`）、`UIGraphicsImageRenderer`（白底 flatten）、`UIImage.jpegData(compressionQuality:)`、`URLSessionWebSocketTask` 不动、Swift Testing、XCUITest。

**TDD 适用范围（与 P1-P6 一致）：**

- **纯逻辑 → TDD**：
  - `AvatarImageCompressor.compressForUpload` 中心裁剪计算 / 输出尺寸 / JPEG 头字节（验证白底 + 编码）
  - `UserRepositoryImpl.updateProfile` HTTP 路径 / 请求体 / 返回解码 / 401 → `APIError.unauthorized`
  - `UploadRepositoryImpl.uploadAvatar` HTTP 路径 / multipart 字段名 / 返回 `avatar_url` / 401 / 400 → `APIError.http`
  - `ProfileEditViewModel`：load 把 currentUser 拷进 form / `save()` 成功覆盖 currentUser / `save()` 401 触发 `onUnauthorized` 回调 / `uploadAvatar()` 成功调 refresh / `uploadAvatar()` 失败保留可恢复 / 上传中 `canSave == false`
- **View → 编译 + 手工 + XCUITest smoke**：`ProfileEditView` 表单可见性、PhotosPicker 弹出（手工）、`UserDetailView` 渲染、`ChatView` 顶部头像可点击（XCUITest 断言 `chatPeerAvatar` 在场 + 点击后 `userDetailRoot` 出现）

**服务端契约改动：** 无。`POST /api/upload/avatar`、`PUT /api/users/me`、`GET /api/users/me` 在服务端均已实现并被 `server/tests/users.test.ts` / `server/tests/upload.test.ts` 覆盖。**P7 不开 server task**——本计划里出现的所有命令都不应改 `server/` 任何文件。

**关键服务端契约速查（实现前必须读懂）：**

- `POST /api/upload/avatar`（multipart，字段名 `file`）：服务端 `flatten` 白底 + `cover` 缩成 400×400 + JPEG quality 80 写盘，紧接着 `UPDATE users SET avatar_url=...`。**这两步不在一个 DB 事务里**——失败路径靠 best-effort 文件清理（`server/src/routes/upload.ts:90-94`）。但成功路径回到客户端时 DB 已写好，响应 `{ avatar_url }`。**iOS 不需要再调 PUT /me 把 avatar_url 写一遍**——服务端已经写好了。客户端只需要在响应回来后刷新本地 `currentUser`。
- `PUT /api/users/me`（JSON body）：服务端 schema 接受 `{ display_name?, avatar_url? }`，但 iOS 端**只**发 `{ display_name }`。Body 为空（两个字段都缺）会被服务端 400 `No fields to update`，VM 层做 input guard 提前过滤"用户没动过 displayName 就不发请求"。响应是完整 `User` 对象（`id, username, email, display_name, avatar_url, created_at`）。
- `GET /api/users/me`：返回完整 `User`。已被 `UserRepositoryImpl.fetchMe` / `AppContainer.refreshCurrentUser` 使用，本阶段不动。
- 所有三个端点都需要 `Authorization: Bearer <token>`；token 失效 → 401 → 触发 `AppContainer.handleUnauthorized()`（与 P3 / P5 路径一致）。

**不在 P7 范围（明确延后）：**

- **手动头像裁剪 UI**：服务端 `cover` 居中裁剪是 source of truth；客户端 `AvatarImageCompressor` 也按相同居中策略裁。不引入"用户拖动选择裁剪框"的交互。
- **外链 avatar URL 输入框**（Web 有，iOS 不做）：移动端 UX 不合理；iOS 头像只能从相册选。
- **i18n / `Localizable.strings`**：P8 主题。本阶段所有文案直接写中文（与现有 `MeView` / `ChatView` 风格一致）。
- **email / username 编辑**：服务端不支持；UI 也不展示编辑入口。
- **删除头像 / 恢复 initials**：服务端 `UPDATE ... COALESCE(...)` 不支持把 avatar_url 设回 null，且 PUT schema 没有"清空"字段。等服务端做 `null` 显式语义再做。
- **从 `ContactsView` 联系人行点击进 UserDetailView**：设计 §8 P7 只要求"从聊天页顶部头像进入"。后续如想让联系人行也能进，注册的 `navigationDestination(for: UserProfile.self)` 已经准备好，加一个 `NavigationLink(value:)` 即可——但不在本阶段。
- **空 displayName 后端校验**：服务端 schema 是 `{ type: 'string', maxLength: 100 }`，未限制 minLength。iOS 沿用——空字符串视为合法，UI 展示时由 `AuthenticatedUser.displayTitle` fallback 到 username。
- **Profile 编辑期间 push 通知 / WS 重连**：与 P3 / P6 已有重连逻辑独立。`ProfileEditView` 期间收到 `presence.online` 等 WS 事件依然由 PresenceStore 路由，不影响表单。

**已知妥协：**

- **头像上传后用 `refreshCurrentUser()` 多打一次 GET /me 而非本地 mutate `currentUser`**：服务端 `POST /upload/avatar` 响应只回 `{ avatar_url }`，本地 mutate `currentUser` 等同于"基于一个非完整响应自己 patch struct 字段"，每次新增 `AuthenticatedUser` 字段都要回来改 mutate 点。`refreshCurrentUser()` 已经存在、有 401 自处理逻辑、与 Web `fetchMe()` 路径一致——一次额外 GET 是正确的代价。
- **`UpdateProfileRequest` 只有 `displayName` 一个字段**：当前业务唯一可编辑字段。如果未来 server 端开放 `bio` / `pronouns` 等，这里再扩。把字段做成 `Optional` + 服务端 `COALESCE` 是已定的契约，但现在只用一个，`Encodable` 单字段最干净。
- **保存 displayName 与上传头像独立两次请求**：用户先上传头像（DB 已写）再改 displayName 时，DB 已经有新 avatar_url。这没问题——两次独立写、各自原子，互不依赖。失败任意一个不会污染另一个。
- **`ProfileEditView` 不做 displayName 长度即时校验**：服务端上限 100 字符，UI 不预先截断；超限由 server 400 反馈（与 register 表单的字段错误处理一致）。日常用户没人会写 100 字以上的 displayName，本端做 maxLength 反而令人迷惑。
- **`ChatView.principalTitle` 整体包 `NavigationLink`，文字 + 头像 + 圆点 + typing 都成为按钮区**：iOS HIG 上"头像 + 名称都跳到对方资料"是常见模式（Telegram / WeChat 都这样）。toolbar.principal 是 NavigationBar 内嵌区域，touch target 上限受 bar 高度约束（≈ 44pt），不再在内部做局部 hit-test。
- **`UserDetailView` 的在线状态读取的是从父级透传的 `PresenceStore`**：与 ChatView 现有路径一致；不订阅 WS、不重复路由。VM-less view，纯展示。

**重要不变式（实现前必须读懂，实现中容易踩到）：**

1. **`POST /api/upload/avatar` 已写库**：iOS 客户端**禁止**在上传响应回来后再调 `PUT /api/users/me` 把 `avatar_url` 写一遍。这条不变式锁住"两次写 DB"的潜在 race。
2. **`PUT /api/users/me` 请求体里不出现 `avatar_url` 键**：`UpdateProfileRequest` 只有 `displayName`。即使 displayName 等于现值也允许发——服务端 `COALESCE($1, display_name)` 是 idempotent 的，但 VM 层做 guard 减无谓请求。
3. **保存按钮在"任一"网络飞行中都禁用**：headers 上传中（`uploadStatus != .idle`）、保存中（`saveStatus != .idle`）任一成立，`canSave == false`。否则容易出"还在传图，用户改了名又点保存，PUT /me 与 POST /avatar 互相覆盖"的时序异常。
4. **头像上传成功后必须 `await refreshCurrentUser()`**：服务端写库的 `avatar_url` 只在 GET /me 才能拿到完整 user。漏掉这一步，本地 `currentUser.avatarUrl` 仍是旧值，MeView / ChatView header 头像不会更新。注：`refreshCurrentUser()` 内部已处理 401，VM 层不需要再 catch。
5. **`AppContainer.currentUser` 是单一真相源**：`ProfileEditViewModel.save()` 成功后写 `container.currentUser = response`；`uploadAvatar()` 成功后让 `container` 自己 GET /me 重写。VM 不复制 currentUser 进自己的 store，只在 Form 层有一份临时编辑稿（`displayNameDraft`）。
6. **`navigationDestination(for: UserProfile.self)` 必须在 NavigationStack 的根处注册**：注册位置 = `ConversationsListView` 与 `ContactsView` 各自的 `NavigationStack { ... }` 内。**禁止**在 ChatView 内部注册——ChatView 是被 push 进来的子节点，自己注册的 destination 只对再下一层生效（SwiftUI 默认从最近的 NavigationStack 取，注册位置错了 push 静默失败）。
7. **`ChatView.principalTitle` 的 `NavigationLink(value: vm.peer)`**：value 必须是 `UserProfile`（`vm.peer` 已经是 `UserProfile`），不是 `vm.peer.id` 或 `Int`。SwiftUI 按值类型 + 注册的 destination 类型匹配。
8. **`UserDetailView` 不带任何 ViewModel**：纯展示，输入只有 `profile: UserProfile` + `presenceStore: PresenceStore?`。订阅 / 写库是上层的职责。这条不变式让它能从任意进入点（聊天页头像、未来联系人行 cell）复用。
9. **`AvatarImageCompressor` 与 `ImageCompressor` 不互相依赖**：两者参数与目标场景不同（头像 400×400 cover-crop / 消息图 1600 长边 fit-inside），合并会让任一改动都波及另一处。保持兄弟文件、各自单测。
10. **PhotosPicker 选完图后的 `Task` 不持有强引用 self**：与 P5 的 ChatView 输入栏一致，避免离开 ProfileEditView 后 Task 仍在跑修改 form 状态。`onChange(of: pickerItem)` 内 `Task { [weak vm] in ... }` 或者捕获 `vm` 但不关心后续 retain 都行——VM 是 `@State` 所有权属于 View，View 销毁时 VM 引用释放，Task 完成时写 nil 不会引发崩溃，但会触发 SwiftUI 警告。**最稳**的写法：`Task { @MainActor in ... }`，捕获 vm 的方法引用。

---

## 开发环境前提

沿用 P1-P6。命令约定：

```bash
# iOS 编译（Debug）
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build

# iOS 单测（Swift Testing）
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test -only-testing:EchoIMTests

# iOS XCUITest（smoke）
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test -only-testing:EchoIMUITests
```

> 如本机没有 `OS=latest` 的 iPhone 15 目标，按 P5 / P6 经验改 `-destination 'platform=iOS Simulator,OS=17.5,name=iPhone 15'`。

服务端不动。仍需保证现有 users / upload 测试通过：

```bash
npm test --prefix server -- users upload
```

工作目录约定：所有 iOS 路径以 `ios-app/EchoIM/` 开头；下方 Step 里 `$BUILD` / `$TEST` / `$UITEST` 占位等价于上面三条 `xcodebuild` 命令。

---

## 文件结构

新增文件：

```
ios-app/EchoIM/
├── Core/
│   └── Utilities/
│       └── AvatarImageCompressor.swift           // 新：400px 居中方形裁剪 + 白底 flatten + JPEG 0.80
└── Features/
    ├── Me/
    │   ├── ProfileEditView.swift                 // 新：编辑表单（头像 PhotosPicker + displayName 输入框）
    │   └── ProfileEditViewModel.swift            // 新：@Observable @MainActor + 上传/保存状态机
    └── Contacts/
        └── UserDetailView.swift                  // 新：对方资料只读卡（大头像 + displayName + @username + 在线状态）
ios-app/EchoIMTests/
├── AvatarImageCompressorTests.swift              // 新（中心裁剪 + 输出 JPEG 头）
├── UserRepositoryUpdateProfileTests.swift        // 新（PUT /api/users/me + 401）
├── UploadRepositoryAvatarTests.swift             // 新（POST /api/upload/avatar + multipart）
└── ProfileEditViewModelTests.swift               // 新（save / upload / 401 / canSave）
ios-app/EchoIMUITests/
├── ProfileEditSmokeTests.swift                   // 新（Me → 编辑资料 → 显示 displayName 字段）
└── UserDetailFromChatSmokeTests.swift            // 新（ChatView 顶部头像点击 → UserDetailView 出现）
```

修改文件：

```
ios-app/EchoIM/
├── Features/
│   ├── Chat/
│   │   └── ChatView.swift                        // principalTitle 包 NavigationLink(value: vm.peer)；前置 28pt AvatarView
│   ├── Conversations/
│   │   └── ConversationsListView.swift           // +navigationDestination(for: UserProfile.self) → UserDetailView
│   ├── Contacts/
│   │   ├── ContactsView.swift                    // +navigationDestination(for: UserProfile.self) → UserDetailView
│   │   └── UserRepository.swift                  // +updateProfile(displayName:token:) protocol + impl
│   ├── Chat/
│   │   └── UploadRepository.swift                // +uploadAvatar(data:token:) protocol + impl
│   └── Me/
│       └── MeView.swift                          // 在身份卡 Section 加 NavigationLink → ProfileEditView
└── ...
```

每个新增文件单一职责。`AvatarImageCompressor` 与 `ImageCompressor` 拆分（不变式 9）；`UserDetailView` 与 `MeView` 拆分（VM-less，可复用）。

---

## Task 1: UserRepository.updateProfile — `PUT /api/users/me` 网络层

**Files:**
- Modify: `ios-app/EchoIM/Features/Contacts/UserRepository.swift`
- Test: `ios-app/EchoIMTests/UserRepositoryUpdateProfileTests.swift`

设计依据：§4.1 `User`、§8 P7 "`UserRepository.updateProfile`"、服务端 `server/src/routes/users.ts:24-87`。

> **实现说明**：项目使用 `PBXFileSystemSynchronizedRootGroup`（Xcode 16+），新建测试文件无需手动改 `project.pbxproj`，文件系统变更自动被 Xcode 识别。

- [x] **Step 1: 写测试 — PUT 路径 + body 字段 + 200 解码 + 401 映射**

```swift
// ios-app/EchoIMTests/UserRepositoryUpdateProfileTests.swift
import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("UserRepository.updateProfile")
struct UserRepositoryUpdateProfileTests {
    @Test
    func updateProfileSendsDisplayNameAndDecodesUser() async throws {
        var capturedRequest: URLRequest?
        let (config, _) = MockURLProtocol.configure { request in
            capturedRequest = request
            let body = """
            { "id": 7, "username": "alice", "email": "a@x.com",
              "display_name": "Alice 2", "avatar_url": "/uploads/avatars/7-1.jpg" }
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UserRepositoryImpl(api: api)

        let user = try await repo.updateProfile(displayName: "Alice 2", token: "tok-1")

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/users/me")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")

        // body 必须是 { "display_name": "Alice 2" }，不能含 avatar_url 键（不变式 2）。
        let bodyData = try #require(request.httpBody ?? Self.bodyData(from: request))
        let json = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["display_name"] as? String == "Alice 2")
        #expect(json["avatar_url"] == nil)
        #expect(json.count == 1)

        #expect(user.id == 7)
        #expect(user.username == "alice")
        #expect(user.displayName == "Alice 2")
        #expect(user.avatarUrl == "/uploads/avatars/7-1.jpg")
    }

    @Test
    func updateProfilePropagatesUnauthorized() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                "{\"error\":\"User no longer exists\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UserRepositoryImpl(api: api)

        do {
            _ = try await repo.updateProfile(displayName: "Whatever", token: "stale")
            Issue.record("expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // 期望路径
        }
    }

    @Test
    func updateProfilePropagates400() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                "{\"error\":\"display_name must NOT have more than 100 characters\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UserRepositoryImpl(api: api)

        do {
            _ = try await repo.updateProfile(displayName: String(repeating: "x", count: 101), token: "t")
            Issue.record("expected APIError.http(400)")
        } catch APIError.http(let status, _) {
            #expect(status == 400)
        }
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
```

- [x] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/UserRepositoryUpdateProfileTests`
Expected: 编译失败（`UserRepository.updateProfile` 未定义）。

- [x] **Step 3: 实现 `UpdateProfileRequest` + `UserRepository.updateProfile`**

```swift
// ios-app/EchoIM/Features/Contacts/UserRepository.swift
import Foundation

protocol UserRepository {
    func fetchMe(token: String) async throws -> AuthenticatedUser
    func searchUsers(query: String, token: String) async throws -> [UserProfile]
    /// P7：单字段更新 displayName。avatar_url 不通过这个端点改（见不变式 1 / 2）。
    func updateProfile(displayName: String, token: String) async throws -> AuthenticatedUser
}

/// 服务端 `PUT /api/users/me` 接收 snake_case 字段名，所以在这里显式 CodingKey。
private struct UpdateProfileRequest: Encodable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
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
        var components = URLComponents()
        components.path = Endpoints.Users.search
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        let path = components.path + "?" + (components.percentEncodedQuery ?? "")
        return try await api.request(path, token: token)
    }

    func updateProfile(displayName: String, token: String) async throws -> AuthenticatedUser {
        try await api.request(
            Endpoints.Users.me,
            method: "PUT",
            token: token,
            body: UpdateProfileRequest(displayName: displayName)
        )
    }
}
```

- [x] **Step 4: 跑测试，确认通过**

Run: `$TEST -only-testing:EchoIMTests/UserRepositoryUpdateProfileTests`
Expected: 3 条全过。

- [x] **Step 5: 同时跑既有 `UserRepositoryTests`，确认未回归**

Run: `$TEST -only-testing:EchoIMTests/UserRepositoryTests`
Expected: 既有 3 条仍全过（fetchMe + 401 + search 不受影响）。

- [x] **Step 6: 提交**

```bash
git add ios-app/EchoIM/Features/Contacts/UserRepository.swift \
        ios-app/EchoIMTests/UserRepositoryUpdateProfileTests.swift
git commit -m "feat(ios): add UserRepository.updateProfile for PUT /api/users/me"
```

---

## Task 2: AvatarImageCompressor — 400px 居中方形 + 白底 + JPEG 0.80

**Files:**
- Create: `ios-app/EchoIM/Core/Utilities/AvatarImageCompressor.swift`
- Test: `ios-app/EchoIMTests/AvatarImageCompressorTests.swift`

设计依据：§6.2 + §11 服务端 `AVATAR_CONFIG`（`outputSize: 400 / outputQuality: 80 / cover-fit / 白底 flatten`）。客户端先做相同处理可显著降低上行体积——服务端再 cover-resize 是 no-op，不会双重有损。

- [x] **Step 1: 写测试 — 横向图裁剪后输出方形 + JPEG 头字节 + 透明 PNG 白底**

```swift
// ios-app/EchoIMTests/AvatarImageCompressorTests.swift
import Foundation
import Testing
import UIKit
@testable import EchoIM

@MainActor
@Suite("AvatarImageCompressor")
struct AvatarImageCompressorTests {
    @Test
    func landscapeImageIsCenterCroppedToSquare() throws {
        // 800×400 横向图 → 期望中心裁出 400×400，再缩到 400×400（无缩放）
        let landscape = Self.makeSolidImage(size: CGSize(width: 800, height: 400), color: .red)
        let data = try #require(AvatarImageCompressor.compressForUpload(landscape))

        let decoded = try #require(UIImage(data: data))
        // UIImage 像素尺寸；scale = 1.0 由 compressor 显式设置。
        #expect(decoded.size.width == 400)
        #expect(decoded.size.height == 400)

        // JPEG SOI 魔数 0xFFD8 + 0xFF（APP0/EXIF）
        #expect(data.count > 4)
        #expect(data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF)

        // 设计 §8 P7 验收点："头像文件 < 200 KB"。
        // 这里是单色块，必然远低于 200KB——这条断言只做"管线没有意外输出几 MB"的安全网；
        // 真实复杂照片的体积上限验证放在 Task 11 实机自测里手工跑。
        #expect(data.count < 200 * 1024)
    }

    @Test
    func portraitImageIsCenterCroppedToSquare() throws {
        let portrait = Self.makeSolidImage(size: CGSize(width: 600, height: 1200), color: .blue)
        let data = try #require(AvatarImageCompressor.compressForUpload(portrait))
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size.width == 400)
        #expect(decoded.size.height == 400)
    }

    @Test
    func smallImageIsUpscaledToOutputSize() throws {
        // 200×200 输入 → 仍输出 400×400（与服务端 cover-fit 行为一致：放大也算 cover）
        let small = Self.makeSolidImage(size: CGSize(width: 200, height: 200), color: .green)
        let data = try #require(AvatarImageCompressor.compressForUpload(small))
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size.width == 400)
        #expect(decoded.size.height == 400)
    }

    @Test
    func transparentImageIsFlattenedToWhiteBackground() throws {
        // 透明 PNG → 编码 JPEG 后中心像素应接近白色（不变式 9 + §6.2 白底处理）
        let transparent = Self.makeTransparentImage(size: CGSize(width: 400, height: 400))
        let data = try #require(AvatarImageCompressor.compressForUpload(transparent))

        let decoded = try #require(UIImage(data: data))
        let centerPixel = try #require(Self.samplePixel(image: decoded, x: 200, y: 200))
        // JPEG 编码会有 1-2 灰阶损失；放宽容差到 ≥ 240 即可视为白底
        #expect(centerPixel.r >= 240)
        #expect(centerPixel.g >= 240)
        #expect(centerPixel.b >= 240)
    }

    @Test
    func returnsNilForUnencodableImage() {
        // 0×0 image 显然没法 jpegData encode；compressor 不抛错，返回 nil 让上层选择失败路径
        let invalid = UIImage()
        let data = AvatarImageCompressor.compressForUpload(invalid)
        #expect(data == nil)
    }

    // MARK: - Helpers

    private static func makeSolidImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func makeTransparentImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            // 不绘制任何东西，保留全透明 alpha=0
        }
    }

    /// 读 image 单像素 RGB；测试用，效率不重要。
    private static func samplePixel(image: UIImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard let cg = image.cgImage else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: -CGFloat(x), y: -CGFloat(y), width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (pixel[0], pixel[1], pixel[2])
    }
}
```

- [x] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/AvatarImageCompressorTests`
Expected: 编译失败（`AvatarImageCompressor` 未定义）。

- [x] **Step 3: 实现 AvatarImageCompressor**

```swift
// ios-app/EchoIM/Core/Utilities/AvatarImageCompressor.swift
import UIKit

/// 与服务端 AVATAR_CONFIG 对齐：cover-fit 居中裁剪到 400×400、白底 flatten、JPEG 0.80。
/// 与 ImageCompressor（消息图 1600px fit-inside）刻意分开（不变式 9）。
enum AvatarImageCompressor {
    static let outputSize: CGFloat = 400
    static let jpegQuality: CGFloat = 0.80

    /// 返回 nil 表示编码失败；调用方按上传失败处理。
    static func compressForUpload(_ image: UIImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }

        let target = CGSize(width: outputSize, height: outputSize)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1                   // 物理像素就是 outputSize；不要按 @2x/@3x 放大
        format.opaque = true               // 白底 + JPEG 编码（不要 alpha 通道）

        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let cropped = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))

            // cover-fit 居中：先按"短边铺满 400"等比缩放，多余的两侧/上下被画布裁掉。
            let imgSize = image.size
            let scale = max(target.width / imgSize.width, target.height / imgSize.height)
            let scaled = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
            let origin = CGPoint(
                x: (target.width - scaled.width) / 2,
                y: (target.height - scaled.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: scaled))
        }

        return cropped.jpegData(compressionQuality: jpegQuality)
    }
}
```

- [x] **Step 4: 跑测试，确认通过**

Run: `$TEST -only-testing:EchoIMTests/AvatarImageCompressorTests`
Expected: 5 条全过。

- [x] **Step 5: 提交**

```bash
git add ios-app/EchoIM/Core/Utilities/AvatarImageCompressor.swift \
        ios-app/EchoIMTests/AvatarImageCompressorTests.swift
git commit -m "feat(ios): add AvatarImageCompressor for 400px square avatar JPEG"
```

---

## Task 3: UploadRepository.uploadAvatar — multipart `POST /api/upload/avatar`

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/UploadRepository.swift`
- Modify: `ios-app/EchoIMTests/ImageTestHelpers.swift`（既有 `MockUploadRepo` / `SuspendableUploadRepo` 也 conform `UploadRepository`，给协议加方法后必须同步补 stub，否则全测试套件编译失败）
- Test: `ios-app/EchoIMTests/UploadRepositoryAvatarTests.swift`

设计依据：§6.1 + §8 P7。复用 `APIClient.upload(...)` multipart 通道（与 P5 `uploadMessageImage` 同一通道，不重写 multipart 框架）。

- [x] **Step 1: 写测试 — 路径 + multipart body + 200 解码 + 401 + 400**

```swift
// ios-app/EchoIMTests/UploadRepositoryAvatarTests.swift
import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("UploadRepository.uploadAvatar")
struct UploadRepositoryAvatarTests {
    @Test
    func uploadAvatarReturnsAvatarURL() async throws {
        var capturedRequest: URLRequest?
        let (config, _) = MockURLProtocol.configure { request in
            capturedRequest = request
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                "{\"avatar_url\":\"/uploads/avatars/7-1745900000000.jpg\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        let url = try await repo.uploadAvatar(
            data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
            token: "tok"
        )
        #expect(url == "/uploads/avatars/7-1745900000000.jpg")

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/upload/avatar")
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.starts(with: "multipart/form-data; boundary="))

        let body = try #require(Self.bodyData(from: request))
        let bodyText = String(decoding: body, as: UTF8.self)
        #expect(bodyText.contains("name=\"file\""))
        #expect(bodyText.contains("filename=\"avatar.jpg\""))
        #expect(bodyText.contains("Content-Type: image/jpeg"))
    }

    @Test
    func uploadAvatarPropagatesUnauthorized() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        do {
            _ = try await repo.uploadAvatar(data: Data([0xFF]), token: "stale")
            Issue.record("expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        }
    }

    @Test
    func uploadAvatarPropagates400ForInvalidImage() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                "{\"error\":\"Invalid image file\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        do {
            _ = try await repo.uploadAvatar(data: Data([0x00]), token: "t")
            Issue.record("expected APIError.http(400)")
        } catch APIError.http(let status, _) {
            #expect(status == 400)
        }
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
```

- [x] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/UploadRepositoryAvatarTests`
Expected: 编译失败（`UploadRepository.uploadAvatar` 未定义）。

- [x] **Step 3: 在 Endpoints 增加 avatar 路径常量**

```swift
// ios-app/EchoIM/Core/Networking/Endpoints.swift
// ...existing enums...

    enum Upload {
        static let messageImage = "api/upload/message-image"
        static let avatar = "api/upload/avatar"          // 新增
    }
```

- [x] **Step 4: 扩展 UploadRepository — 增加 uploadAvatar**

```swift
// ios-app/EchoIM/Features/Chat/UploadRepository.swift
import Foundation

protocol UploadRepository {
    func uploadMessageImage(data: Data, token: String) async throws -> String
    /// P7：上传已压缩的头像 JPEG，返回服务端写库的 avatar_url。
    /// 服务端在响应内已 UPDATE users.avatar_url（不变式 1）；客户端调用方应再调
    /// AppContainer.refreshCurrentUser() 拿完整 user 来同步本地 currentUser（不变式 4）。
    func uploadAvatar(data: Data, token: String) async throws -> String
}

private struct UploadMessageImageResponse: Decodable {
    let mediaUrl: String
}

private struct UploadAvatarResponse: Decodable {
    let avatarUrl: String
}

@MainActor
final class UploadRepositoryImpl: UploadRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func uploadMessageImage(data: Data, token: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.makeMultipartBody(
            fieldName: "file",
            filename: "image.jpg",
            contentType: "image/jpeg",
            payload: data,
            boundary: boundary
        )

        let response: UploadMessageImageResponse = try await api.upload(
            Endpoints.Upload.messageImage,
            boundary: boundary,
            body: body,
            token: token
        )
        return response.mediaUrl
    }

    func uploadAvatar(data: Data, token: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.makeMultipartBody(
            fieldName: "file",
            filename: "avatar.jpg",
            contentType: "image/jpeg",
            payload: data,
            boundary: boundary
        )

        let response: UploadAvatarResponse = try await api.upload(
            Endpoints.Upload.avatar,
            boundary: boundary,
            body: body,
            token: token
        )
        return response.avatarUrl
    }

    private static func makeMultipartBody(
        fieldName: String,
        filename: String,
        contentType: String,
        payload: Data,
        boundary: String
    ) -> Data {
        let crlf = "\r\n"
        var body = Data()
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\(crlf)"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(contentType)\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(payload)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }
}
```

- [x] **Step 5: 同步既有测试 helper — `ImageTestHelpers.swift` 里两个 mock 必须新增 `uploadAvatar` stub**

```swift
// ios-app/EchoIMTests/ImageTestHelpers.swift

// MockUploadRepo 在既有字段下方追加：
final class MockUploadRepo: UploadRepository {
    var uploadResult: String = "/uploads/messages/3-0.jpg"
    var uploadError: Error?
    private(set) var uploadCalls = 0

    // P7：avatar 上传 stub。默认返回固定 URL；测试可按需覆盖。
    var uploadAvatarResult: String = "/uploads/avatars/3-0.jpg"
    var uploadAvatarError: Error?
    private(set) var uploadAvatarCalls = 0

    func uploadMessageImage(data: Data, token: String) async throws -> String {
        uploadCalls += 1
        if let uploadError {
            throw uploadError
        }
        return uploadResult
    }

    func uploadAvatar(data: Data, token: String) async throws -> String {
        uploadAvatarCalls += 1
        if let uploadAvatarError {
            throw uploadAvatarError
        }
        return uploadAvatarResult
    }
}

// SuspendableUploadRepo 也加一份：
final class SuspendableUploadRepo: UploadRepository {
    private var continuation: CheckedContinuation<String, Error>?
    private var avatarContinuation: CheckedContinuation<String, Error>?

    func uploadMessageImage(data: Data, token: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func uploadAvatar(data: Data, token: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.avatarContinuation = continuation
        }
    }

    func resume(with mediaURL: String) {
        continuation?.resume(returning: mediaURL)
        continuation = nil
    }

    func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func resumeAvatar(with avatarURL: String) {
        avatarContinuation?.resume(returning: avatarURL)
        avatarContinuation = nil
    }

    func resumeAvatar(throwing error: Error) {
        avatarContinuation?.resume(throwing: error)
        avatarContinuation = nil
    }
}
```

> 不在 P7 范围内消费这俩新方法（既有 ChatViewModelImageTests 走的是 `uploadMessageImage` 路径），但协议方法不补会让既有测试 target 在 protocol-not-conformed 处全部红。

- [x] **Step 6: 跑测试，确认通过**

Run: `$TEST -only-testing:EchoIMTests/UploadRepositoryAvatarTests`
Expected: 3 条全过。

- [x] **Step 7: 跑既有 UploadRepositoryTests + ChatViewModelImageTests 确认未回归**

Run: `$TEST -only-testing:EchoIMTests/UploadRepositoryTests -only-testing:EchoIMTests/ChatViewModelImageTests`
Expected: 既有用例仍全过（uploadMessageImage 路径与 mock 行为不受影响；新加的 uploadAvatar stub 默认未被调用）。

- [x] **Step 8: 提交**

```bash
git add ios-app/EchoIM/Core/Networking/Endpoints.swift \
        ios-app/EchoIM/Features/Chat/UploadRepository.swift \
        ios-app/EchoIMTests/ImageTestHelpers.swift \
        ios-app/EchoIMTests/UploadRepositoryAvatarTests.swift
git commit -m "feat(ios): add UploadRepository.uploadAvatar for POST /api/upload/avatar"
```

---

## Task 4: ProfileEditViewModel — 表单状态机 + 保存 + 头像上传

**Files:**
- Create: `ios-app/EchoIM/Features/Me/ProfileEditViewModel.swift`
- Test: `ios-app/EchoIMTests/ProfileEditViewModelTests.swift`

设计依据：§4.3 ViewModel 形态、§8 P7、不变式 3 / 4 / 5。VM 保存"表单稿"（`displayNameDraft`）和"两条网络飞行状态"（`saveStatus` / `uploadStatus`）；通过依赖注入的 repo + currentUser 读取器 + currentUser 写入器 + onUnauthorized 回调与外部解耦，便于单测。

- [ ] **Step 1: 写测试 — load / save 成功 / save 401 / upload 成功 / upload 失败 / canSave 互斥**

```swift
// ios-app/EchoIMTests/ProfileEditViewModelTests.swift
import Foundation
import Testing
@testable import EchoIM

// MARK: - Stub repositories

@MainActor
private final class StubUserRepository: UserRepository {
    var fetchMeStub: ((String) async throws -> AuthenticatedUser)?
    var searchStub: ((String, String) async throws -> [UserProfile])?
    var updateProfileStub: ((String, String) async throws -> AuthenticatedUser)?

    func fetchMe(token: String) async throws -> AuthenticatedUser {
        try await (fetchMeStub ?? { _ in throw APIError.invalidResponse })(token)
    }

    func searchUsers(query: String, token: String) async throws -> [UserProfile] {
        try await (searchStub ?? { _, _ in [] })(query, token)
    }

    func updateProfile(displayName: String, token: String) async throws -> AuthenticatedUser {
        try await (updateProfileStub ?? { _, _ in throw APIError.invalidResponse })(displayName, token)
    }
}

@MainActor
private final class StubUploadRepository: UploadRepository {
    var uploadMessageImageStub: ((Data, String) async throws -> String)?
    var uploadAvatarStub: ((Data, String) async throws -> String)?

    func uploadMessageImage(data: Data, token: String) async throws -> String {
        try await (uploadMessageImageStub ?? { _, _ in throw APIError.invalidResponse })(data, token)
    }

    func uploadAvatar(data: Data, token: String) async throws -> String {
        try await (uploadAvatarStub ?? { _, _ in throw APIError.invalidResponse })(data, token)
    }
}

// MARK: - Tests

@MainActor
@Suite("ProfileEditViewModel")
struct ProfileEditViewModelTests {
    private static let baseUser = AuthenticatedUser(
        id: 7,
        username: "alice",
        email: "a@x.com",
        displayName: "Alice",
        avatarUrl: "/uploads/avatars/7-old.jpg"
    )

    private func makeVM(
        currentUser: AuthenticatedUser = baseUser,
        userRepo: StubUserRepository = StubUserRepository(),
        uploadRepo: StubUploadRepository = StubUploadRepository(),
        token: String? = "tok",
        currentUserSetter: @escaping @MainActor (AuthenticatedUser) -> Void = { _ in },
        refreshCurrentUser: @escaping @MainActor () async -> Void = {},
        onUnauthorized: @escaping @MainActor () async -> Void = {}
    ) -> ProfileEditViewModel {
        ProfileEditViewModel(
            currentUser: { currentUser },
            currentUserSetter: currentUserSetter,
            tokenProvider: { token },
            userRepo: userRepo,
            uploadRepo: uploadRepo,
            refreshCurrentUser: refreshCurrentUser,
            onUnauthorized: onUnauthorized
        )
    }

    @Test
    func loadCopiesDisplayNameFromCurrentUser() {
        let vm = makeVM()
        vm.load()
        #expect(vm.displayNameDraft == "Alice")
        #expect(vm.canSave == false, "未改动且无飞行任务，保存不可点（与现值相同）")
    }

    @Test
    func loadFallsBackToUsernameWhenDisplayNameNil() {
        let user = AuthenticatedUser(
            id: 8, username: "bob", email: "b@x.com",
            displayName: nil, avatarUrl: nil
        )
        let vm = makeVM(currentUser: user)
        vm.load()
        // 当 displayName 是 nil/空，draft 也是空字符串；UI placeholder 才能显示 username。
        #expect(vm.displayNameDraft == "")
    }

    @Test
    func canSaveIsFalseForNilDisplayNameWithEmptyDraft() {
        // 关键边界：currentUser.displayName == nil 时，load() 把 draft 归一化成 ""，
        // canSave 必须仍是 false（用户没改东西）。直接 String != String? 比较会误判为
        // 有改动（"" != nil 为 true），这条测试锁住归一化路径。
        let user = AuthenticatedUser(
            id: 8, username: "bob", email: "b@x.com",
            displayName: nil, avatarUrl: nil
        )
        let vm = makeVM(currentUser: user)
        vm.load()
        #expect(vm.displayNameDraft == "")
        #expect(vm.canSave == false)
    }

    @Test
    func canSaveIsTrueOnceDraftDiffersFromCurrent() {
        let vm = makeVM()
        vm.load()
        vm.displayNameDraft = "Alice 2"
        #expect(vm.canSave == true)
    }

    @Test
    func saveSendsTrimmedDraftAndUpdatesCurrentUser() async throws {
        let userRepo = StubUserRepository()
        let updatedUser = AuthenticatedUser(
            id: 7, username: "alice", email: "a@x.com",
            displayName: "Alice 2", avatarUrl: "/uploads/avatars/7-old.jpg"
        )
        var captured: (displayName: String, token: String)?
        userRepo.updateProfileStub = { name, token in
            captured = (name, token)
            return updatedUser
        }
        var setterCalled: AuthenticatedUser?
        let vm = makeVM(
            userRepo: userRepo,
            currentUserSetter: { setterCalled = $0 }
        )
        vm.load()
        vm.displayNameDraft = "  Alice 2  "      // 前后空格

        try await vm.save()

        #expect(captured?.displayName == "Alice 2", "VM 应在发请求前 trim")
        #expect(captured?.token == "tok")
        #expect(setterCalled?.displayName == "Alice 2")
        #expect(vm.saveStatus == .idle)
    }

    @Test
    func saveSkipsRequestWhenDraftEqualsCurrentDisplayName() async throws {
        let userRepo = StubUserRepository()
        var called = false
        userRepo.updateProfileStub = { _, _ in
            called = true
            throw APIError.invalidResponse        // 不应触发
        }
        let vm = makeVM(userRepo: userRepo)
        vm.load()
        // draft 没动；canSave 也是 false，但即使外部强行调 save，也应静默返回（不变式 2）。
        try await vm.save()
        #expect(called == false)
    }

    @Test
    func saveSkipsRequestForNilDisplayNameWithEmptyDraft() async throws {
        // 与 canSaveIsFalseForNilDisplayNameWithEmptyDraft 配对：归一化路径同样要管 save()。
        // 如果 save() 直接 trimmed != currentUser()?.displayName，会把 "" != nil 当成"有改动"
        // 偷偷发一次 PUT /me 把空字符串写进 DB——这是行为 bug。
        let user = AuthenticatedUser(
            id: 8, username: "bob", email: "b@x.com",
            displayName: nil, avatarUrl: nil
        )
        let userRepo = StubUserRepository()
        var called = false
        userRepo.updateProfileStub = { _, _ in
            called = true
            throw APIError.invalidResponse
        }
        let vm = makeVM(currentUser: user, userRepo: userRepo)
        vm.load()
        try await vm.save()
        #expect(called == false)
    }

    @Test
    func save401TriggersOnUnauthorized() async throws {
        let userRepo = StubUserRepository()
        userRepo.updateProfileStub = { _, _ in throw APIError.unauthorized }
        var unauthorizedCalled = false
        let vm = makeVM(
            userRepo: userRepo,
            onUnauthorized: { unauthorizedCalled = true }
        )
        vm.load()
        vm.displayNameDraft = "X"

        do {
            try await vm.save()
            Issue.record("expected APIError.unauthorized to bubble")
        } catch APIError.unauthorized {
            // expected
        }
        #expect(unauthorizedCalled == true)
        #expect(vm.saveStatus == .idle)
    }

    @Test
    func uploadAvatarCallsRefreshOnSuccess() async throws {
        let uploadRepo = StubUploadRepository()
        uploadRepo.uploadAvatarStub = { _, _ in "/uploads/avatars/7-new.jpg" }
        var refreshCalled = false
        let vm = makeVM(
            uploadRepo: uploadRepo,
            refreshCurrentUser: { refreshCalled = true }
        )
        vm.load()

        try await vm.uploadAvatar(data: Data([0xFF, 0xD8]))
        #expect(refreshCalled == true)
        #expect(vm.uploadStatus == .idle)
        #expect(vm.uploadError == nil)
    }

    @Test
    func uploadAvatar401TriggersOnUnauthorized() async throws {
        let uploadRepo = StubUploadRepository()
        uploadRepo.uploadAvatarStub = { _, _ in throw APIError.unauthorized }
        var unauthorizedCalled = false
        let vm = makeVM(
            uploadRepo: uploadRepo,
            onUnauthorized: { unauthorizedCalled = true }
        )
        vm.load()

        do {
            try await vm.uploadAvatar(data: Data([0xFF]))
            Issue.record("expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        }
        #expect(unauthorizedCalled == true)
        #expect(vm.uploadStatus == .idle)
    }

    @Test
    func uploadAvatarFailureLeavesRecoverableState() async throws {
        let uploadRepo = StubUploadRepository()
        uploadRepo.uploadAvatarStub = { _, _ in throw APIError.http(status: 500, body: Data()) }
        let vm = makeVM(uploadRepo: uploadRepo)
        vm.load()

        do {
            try await vm.uploadAvatar(data: Data([0xFF]))
            Issue.record("expected APIError.http")
        } catch APIError.http {
            // expected
        }
        #expect(vm.uploadStatus == .idle, "失败后必须复位状态，UI 才能再次允许选图")
        #expect(vm.uploadError != nil, "失败后应保留错误以供 UI 展示")
    }

    @Test
    func canSaveIsFalseWhileUploading() async throws {
        // 用一个 long-running 的 stub 把 uploadStatus 卡在 .uploading，再断言 canSave。
        let uploadRepo = StubUploadRepository()
        let waitContinuation = AsyncStream<String>.makeStream(of: String.self)
        uploadRepo.uploadAvatarStub = { _, _ in
            // 等外部 yield 一个值再 return
            for await value in waitContinuation.stream {
                return value
            }
            throw APIError.invalidResponse
        }
        let vm = makeVM(uploadRepo: uploadRepo)
        vm.load()
        vm.displayNameDraft = "Alice 2"
        #expect(vm.canSave == true)

        async let upload: Void = vm.uploadAvatar(data: Data([0xFF]))
        // 让上传 task 进入 stub 内（uploadStatus 已切到 .uploading）
        await Task.yield()
        await Task.yield()
        #expect(vm.uploadStatus == .uploading)
        #expect(vm.canSave == false, "上传中保存按钮必须禁用（不变式 3）")

        waitContinuation.continuation.yield("/uploads/avatars/7-new.jpg")
        waitContinuation.continuation.finish()
        try await upload
        #expect(vm.uploadStatus == .idle)
        #expect(vm.canSave == true)
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/ProfileEditViewModelTests`
Expected: 编译失败（`ProfileEditViewModel` 未定义）。

- [ ] **Step 3: 实现 ProfileEditViewModel**

```swift
// ios-app/EchoIM/Features/Me/ProfileEditViewModel.swift
import Foundation
import Observation

enum ProfileEditUploadStatus: Equatable {
    case idle
    case uploading
}

enum ProfileEditSaveStatus: Equatable {
    case idle
    case saving
}

@Observable
@MainActor
final class ProfileEditViewModel {
    // 表单稿
    var displayNameDraft: String = ""

    // 网络飞行状态
    private(set) var saveStatus: ProfileEditSaveStatus = .idle
    private(set) var uploadStatus: ProfileEditUploadStatus = .idle
    private(set) var uploadError: String?

    // 依赖（全部通过闭包/协议注入，便于单测）
    private let currentUser: @MainActor () -> AuthenticatedUser?
    private let currentUserSetter: @MainActor (AuthenticatedUser) -> Void
    private let tokenProvider: @MainActor () -> String?
    private let userRepo: UserRepository
    private let uploadRepo: UploadRepository
    private let refreshCurrentUser: @MainActor () async -> Void
    private let onUnauthorized: @MainActor () async -> Void

    init(
        currentUser: @escaping @MainActor () -> AuthenticatedUser?,
        currentUserSetter: @escaping @MainActor (AuthenticatedUser) -> Void,
        tokenProvider: @escaping @MainActor () -> String?,
        userRepo: UserRepository,
        uploadRepo: UploadRepository,
        refreshCurrentUser: @escaping @MainActor () async -> Void,
        onUnauthorized: @escaping @MainActor () async -> Void
    ) {
        self.currentUser = currentUser
        self.currentUserSetter = currentUserSetter
        self.tokenProvider = tokenProvider
        self.userRepo = userRepo
        self.uploadRepo = uploadRepo
        self.refreshCurrentUser = refreshCurrentUser
        self.onUnauthorized = onUnauthorized
    }

    /// View 出现时调用一次，把 currentUser.displayName 拷进 draft。
    func load() {
        let raw = currentUser()?.displayName ?? ""
        displayNameDraft = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 已有 displayName（去 trim）== 当前 currentUser.displayName 时，保存按钮禁用。
    /// 任一网络飞行中也禁用（不变式 3）。
    /// **关键归一化**：currentUser.displayName 是 String?，draft 是 String。如果直接
    /// `trimmedDraft != currentUser()?.displayName` 比较，nil 会被 Swift 当成与 "" 不等
    /// （Optional.none ≠ Optional.some("")），导致 displayName 为 nil 时 canSave 永远 true。
    /// 必须先把当前值归一化成"trim 过的 String"再比。
    var canSave: Bool {
        guard saveStatus == .idle, uploadStatus == .idle else { return false }
        return trimmedDraft != normalizedCurrentDisplayName
    }

    /// 头像加载预览：currentUser.avatarUrl（上传成功后由 refreshCurrentUser 刷新；本端不缓存 URL）。
    var avatarUrl: String? { currentUser()?.avatarUrl }

    /// 提交 displayName 修改。draft 与现值（归一化后）一致时静默返回（不变式 2）。
    func save() async throws {
        guard saveStatus == .idle else { return }
        let trimmed = trimmedDraft
        guard trimmed != normalizedCurrentDisplayName else { return }
        guard let token = tokenProvider() else { return }

        saveStatus = .saving
        defer { saveStatus = .idle }

        do {
            let updated = try await userRepo.updateProfile(displayName: trimmed, token: token)
            currentUserSetter(updated)
        } catch APIError.unauthorized {
            await onUnauthorized()
            throw APIError.unauthorized
        }
    }

    /// 上传头像：成功后调 refreshCurrentUser 拉一次 GET /me 同步 currentUser（不变式 4）。
    func uploadAvatar(data: Data) async throws {
        guard uploadStatus == .idle else { return }
        guard let token = tokenProvider() else { return }

        uploadStatus = .uploading
        uploadError = nil
        defer { uploadStatus = .idle }

        do {
            _ = try await uploadRepo.uploadAvatar(data: data, token: token)
            await refreshCurrentUser()
        } catch APIError.unauthorized {
            await onUnauthorized()
            throw APIError.unauthorized
        } catch {
            uploadError = String(describing: error)
            throw error
        }
    }

    private var trimmedDraft: String {
        displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 把 currentUser.displayName（Optional<String>）归一化成 trim 过的 String，
    /// 让 canSave / save 用同一基准比较 draft（也是 String）。nil 与空字符串都映射到 ""。
    private var normalizedCurrentDisplayName: String {
        currentUser()?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `$TEST -only-testing:EchoIMTests/ProfileEditViewModelTests`
Expected: 11 条全过。

- [ ] **Step 5: 提交**

```bash
git add ios-app/EchoIM/Features/Me/ProfileEditViewModel.swift \
        ios-app/EchoIMTests/ProfileEditViewModelTests.swift
git commit -m "feat(ios): add ProfileEditViewModel with save/upload state machine"
```

---

## Task 5: ProfileEditView — SwiftUI 编辑表单

**Files:**
- Create: `ios-app/EchoIM/Features/Me/ProfileEditView.swift`

设计依据：§8 P7、Web `client/src/pages/ProfileEditPage.tsx` 的字段结构（精简掉外链 URL 输入框）。本任务无单测——View 层只编译 + 手工 + 后续 Task 10 的 XCUITest 兜底。

- [ ] **Step 1: 实现 ProfileEditView**

```swift
// ios-app/EchoIM/Features/Me/ProfileEditView.swift
import PhotosUI
import SwiftUI
import UIKit

struct ProfileEditView: View {
    @State private var vm: ProfileEditViewModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var saveErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let username: String

    init(
        username: String,
        viewModel: ProfileEditViewModel
    ) {
        self.username = username
        self._vm = State(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                avatarRow
            } header: {
                Text("头像")
            } footer: {
                if let error = vm.uploadError {
                    Text("上传失败：\(error)")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("profileEditUploadError")
                } else {
                    Text("从相册选择一张图片，自动裁剪为 400×400 头像。")
                }
            }

            Section {
                TextField(username, text: $vm.displayNameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("profileEditDisplayName")
            } header: {
                Text("显示名称")
            } footer: {
                Text("好友看到的名字。留空将显示用户名 @\(username)。")
            }
        }
        .navigationTitle("编辑资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: handleSaveTapped) {
                    if vm.saveStatus == .saving {
                        ProgressView()
                    } else {
                        Text("保存")
                    }
                }
                .disabled(!vm.canSave)
                .accessibilityIdentifier("profileEditSaveButton")
            }
        }
        .task { vm.load() }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { @MainActor in
                await handlePickedItem(newItem)
                pickerItem = nil
            }
        }
        .alert(
            "保存失败",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    // MARK: - Avatar row

    @ViewBuilder
    private var avatarRow: some View {
        HStack(spacing: 16) {
            avatarPreview
                .frame(width: 72, height: 72)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                PhotosPicker(
                    selection: $pickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(
                        vm.uploadStatus == .uploading ? "上传中…" : "更换头像",
                        systemImage: "photo.on.rectangle.angled"
                    )
                }
                .disabled(vm.uploadStatus == .uploading)
                .accessibilityIdentifier("profileEditPickAvatar")

                Text("JPEG / PNG / HEIC，自动压缩为 400×400")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let urlString = vm.avatarUrl, let url = Endpoints.absolute(urlString) {
            // 复用 NukeUI LazyImage 的 AvatarView 内部逻辑这里轮子重一些，简单用 AsyncImage：
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    Color(uiColor: .secondarySystemBackground)
                @unknown default:
                    Color(uiColor: .secondarySystemBackground)
                }
            }
        } else {
            Color(uiColor: .secondarySystemBackground)
                .overlay {
                    Text(initials)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var initials: String {
        let trimmed = vm.displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? username : trimmed
        return String(base.prefix(2)).uppercased()
    }

    // MARK: - Actions

    private func handleSaveTapped() {
        Task { @MainActor in
            do {
                try await vm.save()
                dismiss()
            } catch APIError.unauthorized {
                // VM 已触发 onUnauthorized，外层 RootView 会切回 Login；不再展示 alert。
            } catch {
                saveErrorMessage = String(describing: error)
            }
        }
    }

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        guard let raw = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: raw),
              let compressed = AvatarImageCompressor.compressForUpload(image) else {
            // 压缩失败属于"用户挑了张奇怪的图"——保留旧头像，不弹错误（与 Web 行为对齐）。
            return
        }
        do {
            try await vm.uploadAvatar(data: compressed)
        } catch {
            // VM 已经把错误存进 vm.uploadError；UI 在 footer 上展示。
        }
    }
}
```

- [ ] **Step 2: 跑构建确保编译通过**

Run: `$BUILD`
Expected: success。

- [ ] **Step 3: 跑全套单测确认未回归**

Run: `$TEST`
Expected: 既有所有用例 + Task 1-4 新增用例全过。

- [ ] **Step 4: 提交**

```bash
git add ios-app/EchoIM/Features/Me/ProfileEditView.swift
git commit -m "feat(ios): add ProfileEditView form with avatar picker and display name field"
```

---

## Task 6: MeView — 加 NavigationLink 进 ProfileEditView

**Files:**
- Modify: `ios-app/EchoIM/Features/Me/MeView.swift`

设计依据：§8 P7。MeView 已经包了 NavigationStack（既有），加一行 NavigationLink 即可。

- [ ] **Step 1: 在身份卡 Section 下方加"编辑资料"行**

把现有 Form 中身份卡 Section 之后、清缓存 Section 之前的位置插入新 Section：

```swift
// ios-app/EchoIM/Features/Me/MeView.swift
import SwiftUI

struct MeView: View {
    let container: AppContainer
    var onLogout: () async -> Void

    @State private var showClearCacheConfirm = false
    @State private var isClearing = false

    var body: some View {
        NavigationStack {
            if let user = container.currentUser {
                Form {
                    // ...既有身份卡 Section（不动）...
                    Section {
                        HStack(spacing: 16) {
                            AvatarView(user: user, size: 72)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayTitle)
                                    .font(.title3.weight(.semibold))
                                    .accessibilityIdentifier("homeUsername")

                                if let usernameSubtitle = user.usernameSubtitle {
                                    Text(usernameSubtitle)
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

                    // P7：编辑资料入口
                    Section {
                        NavigationLink {
                            ProfileEditView(
                                username: user.username,
                                viewModel: makeProfileEditViewModel()
                            )
                        } label: {
                            Label("编辑资料", systemImage: "person.crop.circle")
                        }
                        .accessibilityIdentifier("meEditProfile")
                    }

                    // ...既有清缓存 Section / 登出 Section 不动...
                    Section {
                        Button(role: .destructive) {
                            showClearCacheConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("清除聊天缓存")
                            }
                        }
                        .accessibilityIdentifier("meClearCache")
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
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog(
            "清除本地聊天缓存？",
            isPresented: $showClearCacheConfirm,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                Task {
                    isClearing = true
                    await container.clearChatCache()
                    isClearing = false
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除本设备上缓存的消息与图片。服务器上的消息不受影响。")
        }
        .overlay(alignment: .center) {
            if isClearing {
                ProgressView("清除中…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    /// VM 的依赖全部从 container 取；currentUser setter 直接写 container.currentUser，
    /// 让 SwiftUI 沿 @Observable 链路重渲染（不变式 5）。
    @MainActor
    private func makeProfileEditViewModel() -> ProfileEditViewModel {
        ProfileEditViewModel(
            currentUser: { container.currentUser },
            currentUserSetter: { container.currentUser = $0 },
            tokenProvider: { [tokenStore = container.tokenStore] in
                (try? tokenStore.load())?.token
            },
            userRepo: container.makeUserRepository(),
            uploadRepo: container.session?.makeUploadRepository()
                ?? UploadRepositoryImpl(api: container.apiClient),
            refreshCurrentUser: { [weak container] in
                await container?.refreshCurrentUser()
            },
            onUnauthorized: { [weak container] in
                await container?.handleUnauthorized()
            }
        )
    }
}
```

- [ ] **Step 2: 跑构建确保编译通过**

Run: `$BUILD`
Expected: success。

- [ ] **Step 3: 提交**

```bash
git add ios-app/EchoIM/Features/Me/MeView.swift
git commit -m "feat(ios): wire MeView NavigationLink to ProfileEditView"
```

---

## Task 7: UserDetailView — 对方资料只读卡

**Files:**
- Create: `ios-app/EchoIM/Features/Contacts/UserDetailView.swift`

设计依据：§8 P7、不变式 8。VM-less 纯展示组件，输入只有 `profile: UserProfile` + 可选的 `presenceStore: PresenceStore?`。

- [ ] **Step 1: 实现 UserDetailView**

```swift
// ios-app/EchoIM/Features/Contacts/UserDetailView.swift
import SwiftUI

struct UserDetailView: View {
    let profile: UserProfile
    let presenceStore: PresenceStore?

    init(profile: UserProfile, presenceStore: PresenceStore? = nil) {
        self.profile = profile
        self.presenceStore = presenceStore
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AvatarView(profile: profile, size: 120)
                    .padding(.top, 32)
                    .accessibilityIdentifier("userDetailAvatar")

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(profile.displayTitle)
                            .font(.title2.weight(.semibold))
                        if isOnline {
                            PresenceDot(size: 10)
                                .accessibilityIdentifier("userDetailOnlineDot")
                        }
                    }
                    .accessibilityIdentifier("userDetailDisplayTitle")

                    if let subtitle = profile.usernameSubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("@\(profile.username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(isOnline ? "在线" : "离线")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                Spacer(minLength: 32)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("资料")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("userDetailRoot")
    }

    private var isOnline: Bool {
        presenceStore?.isOnline(profile.id) == true
    }
}
```

- [ ] **Step 2: 跑构建确保编译通过**

Run: `$BUILD`
Expected: success。

- [ ] **Step 3: 提交**

```bash
git add ios-app/EchoIM/Features/Contacts/UserDetailView.swift
git commit -m "feat(ios): add UserDetailView read-only peer profile card"
```

---

## Task 8: NavigationDestination 注册 — 让 UserProfile 能被 push

**Files:**
- Modify: `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/ContactsView.swift`

设计依据：不变式 6——`navigationDestination(for: UserProfile.self)` 必须在两个 NavigationStack 各自的根处注册，否则 ChatView 内部的 `NavigationLink(value: peer)` push 会静默失败。

- [ ] **Step 1: ConversationsListView 注册 UserProfile destination**

在既有的 `.navigationDestination(for: ChatRoute.self)` 同级追加：

```swift
// ios-app/EchoIM/Features/Conversations/ConversationsListView.swift
// ...VStack/content body 上方既有:
//   .navigationDestination(for: ChatRoute.self) { route in
//       destination(for: route)
//   }
// 紧跟其后追加:

                .navigationDestination(for: UserProfile.self) { profile in
                    UserDetailView(profile: profile, presenceStore: presenceStore)
                }
```

- [ ] **Step 2: ContactsView 注册 UserProfile destination**

ContactsView 也有自己的 NavigationStack，做同样的事：

```swift
// ios-app/EchoIM/Features/Contacts/ContactsView.swift
// ...在既有 .navigationDestination(for: ChatRoute.self) 后追加:

                .navigationDestination(for: UserProfile.self) { profile in
                    UserDetailView(profile: profile, presenceStore: presenceStore)
                }
```

> ContactsView 内部已经持有 `presenceStore: PresenceStore?` 参数（P6 加的），直接复用即可。

- [ ] **Step 3: 跑构建确保编译通过**

Run: `$BUILD`
Expected: success。

- [ ] **Step 4: 提交**

```bash
git add ios-app/EchoIM/Features/Conversations/ConversationsListView.swift \
        ios-app/EchoIM/Features/Contacts/ContactsView.swift
git commit -m "feat(ios): register UserProfile navigation destinations on chats and contacts stacks"
```

---

## Task 9: ChatView — 顶部头像 + 整体 NavigationLink

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatView.swift`

设计依据：§8 P7、不变式 7。ChatView 的 `principalTitle` 改成"小头像 + displayTitle + 圆点 / typing 子行"，整体包 `NavigationLink(value: vm.peer)` 跳到 UserDetailView。

- [ ] **Step 1: 改写 principalTitle**

```swift
// ios-app/EchoIM/Features/Chat/ChatView.swift
// 既有 principalTitle 完整替换为下述实现：

    private var principalTitle: some View {
        NavigationLink(value: vm.peer) {
            HStack(spacing: 8) {
                AvatarView(profile: vm.peer, size: 28)
                    .accessibilityIdentifier("chatPeerAvatar")

                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text(vm.peer.displayTitle)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        if presenceStore?.isOnline(vm.peer.id) == true {
                            PresenceDot(size: 8)
                                .accessibilityIdentifier("chatPeerOnlineDot")
                        }
                    }
                    if vm.peerIsTyping {
                        Text("正在输入...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("chatPeerTyping")
                    }
                }
            }
        }
        .buttonStyle(.plain)               // 不要 NavigationLink 默认蓝色高亮覆盖头像
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chatPrincipalTitle")
    }
```

> 注意：`NavigationLink(value:)` 在 SwiftUI iOS 17 上等价于"按下后向最近 NavigationStack push 一个 value"。父 NavigationStack（ConversationsListView 或 ContactsView）的 `.navigationDestination(for: UserProfile.self)`（Task 8 已注册）会接住这个 value 并渲染 `UserDetailView`。

- [ ] **Step 2: 跑构建确保编译通过**

Run: `$BUILD`
Expected: success。

- [ ] **Step 3: 跑既有 ChatView 相关 XCUITest（PresenceTypingSmokeTests + ChatSmokeTests）确认未回归**

Run: `$UITEST -only-testing:EchoIMUITests/PresenceTypingSmokeTests -only-testing:EchoIMUITests/ChatSmokeTests`
Expected: 既有断言 `chatPrincipalTitle` 仍然在场（新结构里仍然外包了 accessibilityIdentifier）。

- [ ] **Step 4: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatView.swift
git commit -m "feat(ios): add tappable avatar and navigation to peer profile in chat header"
```

---

## Task 10: XCUITest smoke — ProfileEdit + UserDetail

**Files:**
- Create: `ios-app/EchoIMUITests/ProfileEditSmokeTests.swift`
- Create: `ios-app/EchoIMUITests/UserDetailFromChatSmokeTests.swift`

设计依据：与 P5 / P6 既有 smoke 测试一致风格——只断言"屏幕能进、关键 element 在场"，不模拟网络与 PhotosPicker 交互（PhotosPicker 在模拟器上会打开系统相册组件，无法可靠自动化；本地手工测）。

- [ ] **Step 1: 写 ProfileEditSmokeTests — 从 Me tab 进入编辑资料页**

```swift
// ios-app/EchoIMUITests/ProfileEditSmokeTests.swift
import XCTest

final class ProfileEditSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTapEditProfileShowsForm() throws {
        let app = launchAndLogin()

        // 切到"我"tab
        let meTab = app.tabBars.buttons["我"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 5))
        meTab.tap()

        // 点"编辑资料"
        let entry = app.descendants(matching: .any)["meEditProfile"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Me 页应显示编辑资料入口")
        entry.tap()

        // displayName 输入框 + 保存按钮 + 头像 PhotosPicker 触发器都应该可见
        let displayNameField = app.descendants(matching: .any)["profileEditDisplayName"]
        XCTAssertTrue(displayNameField.waitForExistence(timeout: 5))

        let saveButton = app.descendants(matching: .any)["profileEditSaveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))

        let pickAvatar = app.descendants(matching: .any)["profileEditPickAvatar"]
        XCTAssertTrue(pickAvatar.waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    @MainActor
    private func launchAndLogin() -> XCUIApplication {
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
        return app
    }
}
```

- [ ] **Step 2: 写 UserDetailFromChatSmokeTests — 聊天页头像 → UserDetailView**

```swift
// ios-app/EchoIMUITests/UserDetailFromChatSmokeTests.swift
import XCTest

final class UserDetailFromChatSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTapPrincipalAvatarPushesUserDetail() throws {
        let app = launchAndEnterFirstConversation()

        // 顶部头像 + principalTitle 必须在场
        let avatar = app.descendants(matching: .any)["chatPeerAvatar"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 5), "ChatView 顶部应显示对方头像")

        let principal = app.descendants(matching: .any)["chatPrincipalTitle"]
        XCTAssertTrue(principal.exists)

        // 点击 principal 区跳到 UserDetailView
        principal.tap()

        let detailRoot = app.descendants(matching: .any)["userDetailRoot"]
        XCTAssertTrue(detailRoot.waitForExistence(timeout: 5), "应 push 进入 UserDetailView")

        let detailAvatar = app.descendants(matching: .any)["userDetailAvatar"]
        XCTAssertTrue(detailAvatar.exists)

        let detailTitle = app.descendants(matching: .any)["userDetailDisplayTitle"]
        XCTAssertTrue(detailTitle.exists)
    }

    // MARK: - Helpers

    /// 复制 PresenceTypingSmokeTests 的登入 + 选第一行会话路径。
    @MainActor
    private func launchAndEnterFirstConversation() -> XCUIApplication {
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

        let list = app.descendants(matching: .any)["conversationsList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))

        let firstRow = list.descendants(matching: .cell).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        return app
    }
}
```

- [ ] **Step 3: 跑两个 smoke 测试，确认通过（fixture 账号需提前在测试服务端建好；与 P5 / P6 一致）**

Run: `$UITEST -only-testing:EchoIMUITests/ProfileEditSmokeTests -only-testing:EchoIMUITests/UserDetailFromChatSmokeTests`
Expected: 2 个用例通过；如果环境缺 fixture 数据，参考 P6 PresenceTypingSmokeTests 的处理方式记录到 plan 末尾偏差节，但断言路径与 ID 是真实编译过的。

- [ ] **Step 4: 提交**

```bash
git add ios-app/EchoIMUITests/ProfileEditSmokeTests.swift \
        ios-app/EchoIMUITests/UserDetailFromChatSmokeTests.swift
git commit -m "test(ios): add UI smoke for profile edit and user detail navigation"
```

---

## Task 11: 全量构建 + 全量单测 + 实机自测 + 标记 P7 完成

**Files:**
- Modify: `docs/superpowers/plans/2026-04-28-ios-p7-profile-avatar.md`（更新本文件，把 Task 1-10 的 `[ ]` 改为 `[x]`，并记录任何与计划偏差）

- [ ] **Step 1: 跑全量构建**

Run: `$BUILD`
Expected: success；warnings 为零或与 P6 完成时一致。

- [ ] **Step 2: 跑全量单测**

Run: `$TEST`
Expected: 所有 EchoIMTests 用例通过——包含 P7 新增 `UserRepositoryUpdateProfileTests` (3) + `AvatarImageCompressorTests` (5) + `UploadRepositoryAvatarTests` (3) + `ProfileEditViewModelTests` (11)，共 22 条新增。

- [ ] **Step 3: 跑全量 XCUITest smoke**

Run: `$UITEST`
Expected: 既有 smoke + Task 10 新增 2 个全过。

- [ ] **Step 4: 实机自测脚本（手工跑一遍）**

  打开 EchoIM iOS App，使用真实测试账号登录，按以下顺序操作并观察结果：

  1. **改名片**：Me → 编辑资料 → 修改 displayName → 保存 → 返回 Me 页确认 displayTitle 已变；杀 App 重开也仍然是新名字。
  2. **改头像**：Me → 编辑资料 → 更换头像 → 选一张相册图片 → 等待"上传中…"消失 → 头像预览刷成新图；返回 Me 页 + 切到"聊天"tab 看会话列表对端头像（如果对方角度看自己的话）也是新的。
  3. **改头像后对方端看到新头像的路径**：服务端**不会**主动推 `user.updated` WS 事件，对方拿新头像 URL 只走两条 REST 路径：
     - `GET /api/conversations` 返回的 `peer_avatar_url`（`server/src/routes/conversations.ts:19`）
     - `GET /api/friends` 返回的 `avatar_url`（`server/src/routes/friends.ts:10`）

     这两条都不是"看自己"的 GET /me。所以对方端要做以下任一动作才会看到我的新头像：（a）在会话列表 / 联系人 tab 下拉刷新；（b）杀 App 重启重新拉列表；（c）WS 重连后服务端会 push `connection.ready`，触发对方端 §7.5 step 1 的会话列表刷新。**自己端**这一侧——MeView / ChatView 顶部"我"的小头像不会出现（自己端没人会渲染自己的小头像作为 peer）。ChatView principalTitle 的对端资料应与对端 GET /me 看到的自身资料保持字段语义一致；但本端刷新来源是 conversations / friends 的 peer 数据，不是对端 GET /me。
  4. **聊天页头像点击进入 UserDetailView**：从会话列表打开任意聊天 → 点击顶部对方头像或文字 → 进入对方资料页（大头像 + displayName + @username + 在线/离线状态）。
  5. **在线状态在 UserDetailView 跟随 PresenceStore 变化**：让对方端登出，UserDetailView 在线圆点应该消失，文字变"离线"（≤ 5 秒级）。
  6. **保存空 displayName**：编辑资料 → 把 displayName 清空 → 保存 → 返回 Me 页 → displayTitle fallback 到 username（设计 §4.1 `displayTitle` 行为）。
  7. **保存与现值相同的 displayName**：保存按钮 disabled，无法点击；canSave 不变式 5 验证。
  8. **上传期间保存按钮禁用**：选一张大图，上传期间保存按钮应该 disabled（这条若难以观察到，可在 ProfileEditViewModelTests `canSaveIsFalseWhileUploading` 已经保证）。
  9. **头像文件 < 200 KB（设计 §8 P7 验收点）**：用一张真实复杂相册照片（建议带高频细节，如人像 / 风景）传一遍，在服务端 `uploads/avatars/<userId>-*.jpg` 看落盘文件 size 应 < 200 KB；或在 Xcode 调试 / 控制台打印一次 `AvatarImageCompressor.compressForUpload` 返回的 `data.count`。客户端先压再上传，服务端 cover-resize 是 no-op，所以"客户端 data.count < 200KB" ≈ "服务端落盘文件 < 200KB"。如超 200KB，记到偏差节，不阻塞 P7 完成（极端高频图可放宽到 < 250KB；真实高于这个值再考虑降 quality）。

  把异常项记录到本计划文件末尾的"实机偏差"节。

- [ ] **Step 5: 把本计划 Task 1-10 的 checkbox 改为 `[x]`**

直接编辑 `docs/superpowers/plans/2026-04-28-ios-p7-profile-avatar.md` 顶部的 Task 标题与 Step 复选框；如有与计划不符的实现，在该 Task 末尾用一段引用注明"实际偏差"。

- [ ] **Step 6: 最终提交**

```bash
git add docs/superpowers/plans/2026-04-28-ios-p7-profile-avatar.md
git commit -m "docs(ios): mark P7 plan fully implemented"
```

---

## 依赖关系（与设计 §8 一致）

```
P1 (脚手架+登录)
 └─→ P7 (Profile 编辑) [本阶段]
     └─→ P8 (打磨+测试+i18n)
```

P7 与 P2-P6 没有强依赖（仅 ChatView 顶部头像扩展用到了 P6 的 PresenceStore，VM-less view 接口设计已是可选项）。技术债清单全部往 P8 推。

---

## 上下文索引（实现时常用的"看一眼就知道为啥这么写"的位置）

- 服务端 avatar 上传 + DB 写入（不变式 1）：`server/src/routes/upload.ts:31-107`
- 服务端 PUT /me 字段 schema（不变式 2）：`server/src/routes/users.ts:24-87`
- 服务端 GET /me 401 语义（与 `refreshCurrentUser` 配合）：`server/src/routes/users.ts:11-22`
- Web 端 ProfileEdit 整体流程（参考但 iOS 简化）：`client/src/pages/ProfileEditPage.tsx`
- Web 端 auth store 的 fetchMe / updateProfile 模式：`client/src/stores/auth.ts:53-73`
- iOS 既有 `AppContainer.refreshCurrentUser`（不变式 4 的实现入口）：`ios-app/EchoIM/App/AppContainer.swift:84-95`
- iOS 既有 multipart 上传通道（Task 3 复用）：`ios-app/EchoIM/Core/Networking/APIClient+Upload.swift`
- iOS 既有图片压缩（Task 2 兄弟参考）：`ios-app/EchoIM/Core/Utilities/ImageCompressor.swift`
- iOS 既有 ChatView principalTitle（Task 9 改写起点）：`ios-app/EchoIM/Features/Chat/ChatView.swift:80-100`
- iOS 既有 NavigationStack + navigationDestination 模式（Task 8 模板）：`ios-app/EchoIM/Features/Conversations/ConversationsListView.swift:55-72`
