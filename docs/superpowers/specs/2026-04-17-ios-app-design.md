# EchoIM iOS 客户端设计文档

**日期：** 2026-04-17
**范围：** 与现有 Web 端（`/client`）保持功能对等的 iOS 原生客户端

---

## 0. 背景与目标

EchoIM 已有完整的服务端（`/server`，12 个阶段全部完成）和 Web 客户端（`/client`，React + Vite）。本设计覆盖 iOS 端的从零实现，目标是**与 Web 端功能对等**——不多不少。

**明确不做的事**：
- 不接入 APNs 推送（作品集范围，后台不收消息是可接受的）
- 不做群聊、语音、视频、文件等 Web 端也没有的能力
- 不做自定义主题（跟随系统 Light/Dark 即可）

**目标设备/系统**：iOS 17+，iPhone only（不做 iPad 自适应布局）。

---

## 1. 技术栈与架构选型

### 1.1 技术栈

| 层 | 选型 | 理由 |
|----|------|------|
| UI | SwiftUI（iOS 17+，`@Observable` 宏） | 与 React 声明式一致，减少样板代码 |
| 状态管理 | `@Observable` + `@State` + `@Bindable` | iOS 17+ 原生方案，不引入 TCA/ReduxSwift 等第三方框架 |
| 架构模式 | **MVVM**（View + ViewModel + Repository） | 团队心智负担低；ViewModel 在 feature-screen 粒度使用，不每个子组件都建 VM |
| 网络 | URLSession + async/await | 标准库足够；不引 Alamofire |
| WebSocket | `URLSessionWebSocketTask` | 系统自带；不引 Starscream |
| 持久化 | SwiftData（`@Model`） | iOS 17+ 原生；替代 CoreData/Realm |
| 图片缓存 | Nuke + NukeUI | 内存 + 磁盘双层缓存，SwiftUI 友好 |
| 凭证存储 | KeychainAccess | 最小封装，避免直接操作 SecItem |
| DI | 手写依赖容器 + factory 方法 | 项目规模下框架过重 |

### 1.2 架构分层

```
┌──────────────────────────────────────────────────┐
│  View (SwiftUI)                                  │
│    - LoginView, ChatView, ConversationsListView  │
│    - 纯 UI，不持网络/数据库引用                   │
└──────────────────┬───────────────────────────────┘
                   │ @Observable binding
┌──────────────────▼───────────────────────────────┐
│  ViewModel (@Observable, MainActor)              │
│    - ChatViewModel, AuthViewModel                │
│    - 业务逻辑、乐观更新、状态机                   │
└──────────────────┬───────────────────────────────┘
                   │ protocol call
┌──────────────────▼───────────────────────────────┐
│  Repository (protocol + impl)                    │
│    - MessageRepository, FriendRepository         │
│    - 数据来源抽象（API / SwiftData / 内存）       │
└─────┬──────────────────┬─────────────────────────┘
      │                  │
┌─────▼─────┐      ┌─────▼──────┐
│ APIClient │      │ SwiftData  │
│ + WSClient│      │ Store      │
└───────────┘      └────────────┘
```

**关键约束**：
- View 不持有 Repository / APIClient 引用
- ViewModel 不直接用 URLSession / SwiftData API
- 所有 `@Observable` 类都标 `@MainActor`，后台工作通过 `Task.detached` 或 Repository 内部 actor 隔离
- **SwiftData 并发**：`ModelContainer` 是线程安全的、可跨 actor 共享；`ModelContext` **不是 Sendable**，**严禁跨 actor 传递或共享**。统一规则：
  - DI 层只注入 `ModelContainer`
  - 落库 / 查询都封装在 `@ModelActor` 类型里（如 `MessageStore`、`ConversationMetaStore`），actor 内部按需 `ModelContext(container)` 创建自己的 context
  - ViewModel 调用 `await store.xxx(...)`，不接触 context；UI 层如果要 SwiftUI `@Query` 自动绑定，仍然只在 MainActor 上用，且用的是 `\.modelContext` 环境注入，不与后台 actor 共享同一个 context 实例

---

## 2. 工程结构与依赖注入

### 2.1 目录

```
ios-app/EchoIM/
├── App/
│   ├── EchoIMApp.swift              // @main
│   ├── AppContainer.swift           // DI 容器
│   └── RootView.swift               // 根据登录态切换 Login / Main
├── Core/
│   ├── Networking/
│   │   ├── APIClient.swift          // REST 基础
│   │   ├── APIError.swift
│   │   ├── Endpoints.swift
│   │   └── WebSocketClient.swift    // WS 生命周期
│   ├── Storage/
│   │   ├── KeychainTokenStore.swift
│   │   ├── SwiftDataContainer.swift
│   │   └── Models/                  // @Model CachedMessage 等
│   ├── Utilities/
│   │   ├── ImageCompressor.swift
│   │   ├── NetworkMonitor.swift
│   │   └── DateParser.swift         // ISO 8601 fractional seconds
│   └── DI/
│       └── AppContainer.swift       // 工厂方法暴露 Repository
├── Features/
│   ├── Auth/
│   │   ├── LoginView.swift
│   │   ├── LoginViewModel.swift
│   │   ├── RegisterView.swift
│   │   ├── RegisterViewModel.swift
│   │   └── AuthRepository.swift
│   ├── Conversations/
│   ├── Chat/
│   │   ├── ChatView.swift
│   │   ├── ChatViewModel.swift
│   │   ├── MessageBubble.swift
│   │   └── ImageMessageBubble.swift
│   ├── Contacts/
│   ├── Profile/
│   └── Shared/
│       └── Stores/
│           ├── PresenceStore.swift      // @Observable
│           └── TypingStore.swift
├── Shared/
│   ├── Extensions/
│   └── Resources/
│       ├── Localizable.strings
│       └── Assets.xcassets
└── Tests/
    ├── UnitTests/                       // Swift Testing
    └── UITests/                         // XCUITest
```

### 2.2 DI 容器

`AppContainer` 持有**与登录态无关**的依赖（API 客户端、Keychain），以及**当前登录用户**的 `UserSession`——后者承载 ModelContainer 等用户相关资源。登出时整体替换 `UserSession`。

```swift
@MainActor
final class AppContainer {
    let tokenStore: KeychainTokenStore
    let apiClient: APIClient
    var session: UserSession?            // 未登录时为 nil

    init(tokenStore: KeychainTokenStore, apiClient: APIClient) {
        self.tokenStore = tokenStore
        self.apiClient = apiClient
    }

    /// 登录或冷启动检测到 token 时调用
    func bootstrapSession(userId: Int) throws {
        self.session = try UserSession(userId: userId, apiClient: apiClient)
    }

    /// 登出 / token 失效时调用。**分两阶段**——先释放 session（让 ModelContainer 失引、
    /// SwiftData 关文件句柄），再删磁盘文件。文件清理由 AppContainer 做而不是 UserSession，
    /// 因为"删自己宿主的文件"在时序上无法自证（删的时候自己还活着 = ModelContainer 还活着）。
    func tearDownSession() async {
        guard let userId = session?.userId else { return }

        // 阶段 1：Nuke 与 SwiftData 生命周期无关，独立清
        ImagePipeline.shared.cache.removeAll()

        // 阶段 2：放掉 session（含 ModelContainer）；yield 一次让 actor / autorelease 有机会排空
        self.session = nil
        await Task.yield()

        // 阶段 3：此时 SwiftData 已经释放文件句柄，安全删目录
        let dir = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)")
        try? FileManager.default.removeItem(at: dir)
    }

    func makeAuthRepository() -> AuthRepository {
        AuthRepositoryImpl(api: apiClient, tokenStore: tokenStore)
    }
}

/// 一个登录用户对应一个 UserSession；不同用户互不可见。
/// **不暴露"自清理"方法**——自清理存在时序悖论（删的时候自己还活着），统一交给 AppContainer。
@MainActor
final class UserSession {
    let userId: Int
    let modelContainer: ModelContainer        // 按 userId 分库
    let wsClient: WebSocketClient
    let presenceStore = PresenceStore()
    let typingStore = TypingStore()

    init(userId: Int, apiClient: APIClient) throws {
        self.userId = userId
        // 按 userId 隔离：每个用户一个独立的 store URL
        let storeURL = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)/cache.sqlite")
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try storeURL.deletingLastPathComponent().setResourceValues(resourceValues)

        let config = ModelConfiguration(url: storeURL)
        self.modelContainer = try ModelContainer(
            for: CachedMessage.self, ConversationMeta.self,
            configurations: config
        )
        self.wsClient = WebSocketClient(apiClient: apiClient)
    }

    // ModelActor 内部包：每个 store 持自己的 ModelContext，调用方只 await
    func messageStore() -> MessageStore { MessageStore(container: modelContainer) }
    func conversationMetaStore() -> ConversationMetaStore { ConversationMetaStore(container: modelContainer) }

    func makeChatViewModel(conversationId: Int?, peerId: Int) -> ChatViewModel { ... }
}

/// @Model 实体严禁跨 actor 边界。Store 内部碰 SwiftData model，出口一律映射成 Sendable 的
/// plain struct——Message 对消息刚好够用（§4.1 已定义、字段完全对齐）；ConversationMeta 没有
/// 天然对应类型，单独定义 ConversationMetaSnapshot（见 §5.2）。
@ModelActor
actor MessageStore {
    /// 写入：传进来的是 Sendable Message，store 内部转 @Model CachedMessage 落盘
    func append(_ msgs: [Message]) throws { /* uses modelContext, 内部 @Model 不外泄 */ }

    /// 读取：fetch @Model → 映射成 Message 返回，@Model 绝不出 actor
    func loadOlder(conversationId: Int, before: Int, limit: Int) throws -> [Message] { ... }
    func loadLatest(conversationId: Int, limit: Int) throws -> [Message] { ... }
}

@ModelActor
actor ConversationMetaStore {
    func upsert(_ snapshot: ConversationMetaSnapshot) throws { ... }
    func load(conversationId: Int) throws -> ConversationMetaSnapshot? { ... }
    func loadAll() throws -> [ConversationMetaSnapshot] { ... }
}
```

`RootView` 从 `@Environment` 拿到 `AppContainer`：未登录态渲染 LoginView/RegisterView；已登录态从 `container.session!` 调 factory 构造 ViewModel。

---

## 3. 开发切片策略

**选择：垂直切片（Plan B）**。每个阶段交付一个能运行、能演示的增量，而不是先全部 Model → 全部 Repository → 全部 UI 的水平切法。

**理由**：
- 水平切法在最后联调前没有任何可演示成果，风险集中在末期
- 垂直切法每个阶段都能真机试玩，提前发现设计问题
- MVVM 的分层天然支持 feature-by-feature 交付

具体阶段见第 8 节。

---

## 4. 数据模型与 ViewModel 形态

### 4.1 服务端数据模型回顾

所有业务 ID 都是 PostgreSQL `SERIAL`（整数，**全局递增**，不是每会话独立）。这一点对第 5 节的缓存设计很关键。

```swift
struct User: Codable, Identifiable {
    let id: Int
    let username: String
    let email: String
    let displayName: String?
    let avatarUrl: String?
}

struct Conversation: Identifiable {
    let id: Int
    let createdAt: Date
    let peer: User                      // 由服务端的 peer_* 平铺字段在 init(from:) 里聚合
    let lastMessageBody: String?
    let lastMessageType: String?        // "text" | "image"
    let lastMessageSenderId: Int?
    let lastMessageAt: Date?
    let lastReadMessageId: Int?
    let unreadCount: Int
}

// 服务端返回的是平铺字段：peer_id、peer_username、peer_display_name、peer_avatar_url、
// last_message_body、last_message_sender_id、last_message_at、last_message_type 等。
// 客户端在 Decodable 里聚合成嵌套 User，下游使用更方便。
extension Conversation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, createdAt
        case peerId, peerUsername, peerDisplayName, peerAvatarUrl
        case lastMessageBody, lastMessageType, lastMessageSenderId, lastMessageAt
        case lastReadMessageId, unreadCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        peer = User(
            id: try c.decode(Int.self, forKey: .peerId),
            username: try c.decode(String.self, forKey: .peerUsername),
            email: "",                           // 服务端不返回，前端不需要
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

> **关于 keyDecodingStrategy**：APIClient 全局用 `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`，所以服务端的 `peer_id` / `last_message_at` 等会被自动转成 camelCase 后再走 `CodingKeys` 匹配。

```swift

struct Message: Codable, Identifiable {
    let id: Int
    let conversationId: Int
    let senderId: Int
    let body: String?                   // text 必填
    let messageType: String             // "text" | "image"
    let mediaUrl: String?               // image 必填
    let createdAt: Date
    let clientTempId: String?           // 仅发给发送者自己的那条带
}
```

### 4.2 本地状态附加字段

服务端 Message 是不可变的，但客户端需要跟踪发送状态：

```swift
enum MessageSendState {
    case pending        // 乐观发送中
    case sent           // 已确认
    case failed(Error)  // 失败（显示重试按钮）
}

struct LocalMessage {
    let message: Message
    var sendState: MessageSendState
    var localImageData: Data?          // 图片消息：本地原始数据（避免 bubble 闪烁重加载）
}
```

### 4.3 ViewModel 形态

```swift
@Observable
@MainActor
final class ChatViewModel {
    // 状态
    var messages: [LocalMessage] = []
    var isLoadingOlder = false
    var oldestCachedMessageId: Int?      // 连续后缀不变式
    var newestCachedMessageId: Int?
    var typingPeers: Set<Int> = []
    var imageSendStages: [String: ImageSendStage] = [:]  // [clientTempId: stage]

    // 依赖
    private let messageRepo: MessageRepository
    private let wsClient: WebSocketClient
    private(set) var conversationId: Int?  // 草稿态可能为 nil，首条消息 201 后回填
    private let peerId: Int                 // 永远已知，作为 sendMessage 的 recipient_id

    // 生命周期
    func onAppear() async { ... }        // 读缓存 → 补拉最新 → 标已读
    func onDisappear() { ... }           // 取消订阅

    // 行为
    func sendText(_ body: String) async { ... }
    func sendImage(_ data: Data) async { ... }
    func retry(clientTempId: String) async { ... }
    func loadOlder() async { ... }
    func handleWSEvent(_ event: WSEvent) { ... }
}
```

**粒度原则**：一个 ViewModel 对应一个"屏幕"或一个强内聚的功能区。`MessageBubble` 这种纯渲染组件不需要 VM。

**草稿对话（draft conversation）场景**：服务端的对话是**首条消息插入时才创建**的（`messages.ts` advisory lock）。所以从好友列表点开聊天时，如果两人从未发过消息，`conversationId` 还不存在。`ChatViewModel` 必须支持这种状态：

- `conversationId: Int?` 初始可为 `nil`
- 发送接口入参是 `recipient_id`（即 `peerId`），**不需要 `conversation_id`**——服务端在事务里 find-or-create
- 首条消息 201 响应回来后，从 `msgRow.conversation_id` 回填 `self.conversationId`
- 在 `conversationId == nil` 期间：本地缓存 / 已读上报 / WS typing 都跳过（没东西可读、可标、可发 typing）
- WS `message.new` 到达时，如果当前是草稿态且 `payload.sender_id == peerId`，要把 `conversationId` 回填、走 §5.3 场景 A 拉一次最新——对方先发了消息把对话激活了

---

## 5. SwiftData 本地缓存策略

### 5.1 核心问题

服务端用**全局 SERIAL ID**，意味着同一会话的消息 ID 可能是 `[12, 47, 89, 103, ...]`——中间跳号，因为别的会话插入了消息。

**这带来一个棘手的问题**：客户端本地缓存无法用"ID 连续性"判断是否丢消息。例如缓存里最新是 89，下次拉到 103，你无法确认 89 和 103 之间有没有"属于本会话但被跳过"的消息。

### 5.2 解决方案：连续后缀不变式

**不变式**：每个会话的本地缓存始终是"服务端真实消息序列的一段**连续后缀**或**连续区间**"。用两个字段追踪：

```swift
@Model
final class ConversationMeta {
    @Attribute(.unique) var conversationId: Int
    var oldestCachedMessageId: Int?     // 本地缓存中最旧一条的 ID
    var newestCachedMessageId: Int?     // 本地缓存中最新一条的 ID
    var lastReadMessageId: Int?
    var unreadCount: Int
    var lastMessageBody: String?
    var lastMessageType: String?
    var lastMessageAt: Date?
}

@Model
final class CachedMessage {
    @Attribute(.unique) var id: Int
    var conversationId: Int
    var senderId: Int
    var body: String?
    var messageType: String
    var mediaUrl: String?
    var createdAt: Date
}
```

**@Model 不跨 actor**：`ConversationMeta` 和 `CachedMessage` 是 `@Model`（非 Sendable），仅在 `MessageStore` / `ConversationMetaStore` 内部使用，**不得返回给 ViewModel**。出 actor 边界统一映射成 Sendable plain struct：

- **消息方向**：直接复用 §4.1 的 `Message`（字段与 `CachedMessage` 完全对齐，无需新类型）
- **会话元数据方向**：定义 `ConversationMetaSnapshot`

```swift
struct ConversationMetaSnapshot: Sendable, Equatable {
    let conversationId: Int
    let oldestCachedMessageId: Int?
    let newestCachedMessageId: Int?
    let lastReadMessageId: Int?
    let unreadCount: Int
    let lastMessageBody: String?
    let lastMessageType: String?
    let lastMessageAt: Date?
}

extension ConversationMeta {
    func snapshot() -> ConversationMetaSnapshot {
        .init(conversationId: conversationId,
              oldestCachedMessageId: oldestCachedMessageId,
              newestCachedMessageId: newestCachedMessageId,
              lastReadMessageId: lastReadMessageId,
              unreadCount: unreadCount,
              lastMessageBody: lastMessageBody,
              lastMessageType: lastMessageType,
              lastMessageAt: lastMessageAt)
    }
}

extension CachedMessage {
    /// 和 API Message 结构对齐；ViewModel / Repository 层统一用 Message
    func asMessage() -> Message {
        Message(id: id, conversationId: conversationId, senderId: senderId,
                body: body, messageType: messageType, mediaUrl: mediaUrl,
                createdAt: createdAt, clientTempId: nil)
    }
}
```

Store 方法签名强制这一约定（见 §2.2 `MessageStore` / `ConversationMetaStore`）：`loadOlder` 返回 `[Message]`、`load(conversationId:)` 返回 `ConversationMetaSnapshot?`，不泄漏 `@Model`。

### 5.3 三个场景的处理

**场景 A：冷启动 / 初次进入聊天页**
- 读 `ConversationMeta`：如果不存在或 `newestCachedMessageId == nil` → 调 `GET /api/conversations/:id/messages`（无 cursor，拉最新 50）
- 把返回的 50 条落盘，设 `oldestCachedMessageId = 最小 ID`、`newestCachedMessageId = 最大 ID`
- 这 50 条天然是连续后缀（服务端按 id DESC LIMIT 50，就是最新的连续 50 条）

**场景 B：有缓存，补拉最新（overlap merge）**
- 读缓存已有数据 → 渲染
- 调 `GET ?after=<newestCachedMessageId>`
- 返回的条目 ID **严格大于** `newestCachedMessageId`，直接 append 到缓存后端
- 更新 `newestCachedMessageId` 为返回中的最大 ID
- **不变式保持**：因为 `after` 查询语义就是 "id > cursor ORDER BY id ASC"，新拿到的一定紧接在旧缓存之后

**场景 C：有缓存，补拉返回满一页（cursor 翻页前进）**
- 如果 `GET ?after=<newestCachedMessageId>&limit=50` 返回正好 50 条（达到 limit 上限），说明 newest 之后可能还有更多
- **循环翻页**：把返回中的 max id 作为新 cursor，继续 `?after=<新 cursor>&limit=50`，每批 append 到尾部、推进 `newestCachedMessageId`，直到某次返回 < 50 条
- **安全阀**：单次补拉最多翻 20 页（1000 条）。超过视为异常（客户端长期离线 / 服务端异常），停止补拉、记日志，已经写入的部分依然有效
- **不变式保持**：每批都是"严格大于上一个 cursor"的连续 ID 段，按顺序 append 即可
- 为什么不擦库？SwiftData 是用户上滑攒出来的离线缓存，擦掉会破坏离线滚动体验；翻页前进的代码量并不显著更大，且天然带 buffer

**上滑加载历史消息**：

VM 额外维护 `oldestDisplayedMessageId`（当前已渲染的最早一条 id；不变式保证它 ≥ `oldestCachedMessageId`）。设 `PAGE_SIZE = 50`。

1. **先查本地**：`SwiftData.fetch(conversationId == X && id < oldestDisplayedMessageId, sort: id DESC, limit: PAGE_SIZE)`，得到 N 条
2. **本地够用**（N == PAGE_SIZE）→ 全部用本地，零网络，更新 `oldestDisplayedMessageId = min(本地返回的 id)`
3. **本地不够**（N < PAGE_SIZE）→ 缺 `(PAGE_SIZE - N)` 条，调 `GET ?before=<oldestCachedMessageId>&limit=<PAGE_SIZE - N>`
   - 注意 cursor 是 `oldestCachedMessageId`（缓存的下边界），不是 `oldestDisplayedMessageId`——前者之前才是真未缓存区间
   - 远端返回写盘 + 更新 `oldestCachedMessageId = min(返回中的 id)`
   - 渲染：本地 N 条 + 远端 (PAGE_SIZE - N) 条，按 id 排序拼到顶端
   - **不变式保持**：`before` 查询语义 "id < cursor ORDER BY id DESC"，新拿到的紧接在旧缓存最旧端之前
4. **远端返回空数组** → 已到会话最早一条，置 `hasReachedOldest = true`，后续上滑不再请求

**为什么不一律拿 50**：本地缓存命中时，没必要让服务端再送一遍——这要求服务端 `messages` 接口支持 `?limit=N`（见 §11 服务端契约依赖）。

**WS 实时消息到达**：
- `message.new` 事件：如果 `message.id == newestCachedMessageId + 1`，或者"发送者就是自己"（刚刚乐观发的），直接 append，更新 `newestCachedMessageId`
- 如果 `message.id > newestCachedMessageId + 1` 且非自己发的 → 中间有跳号，但因为 SERIAL 全局递增，跳号几乎一定是别的会话造成的，不是 gap；直接 append 即可
- 判断 gap 只发生在"重连后补拉"的场景，不在单条 WS 推送时判断

### 5.4 存储位置

- SwiftData store 路径：`.applicationSupport/EchoIM/users/<userId>/cache.sqlite`（**按用户分库**，见 §5.5）
- 父目录设置 `URLResourceValues.isExcludedFromBackup = true`，避免 iCloud 备份占用用户空间
- Nuke 磁盘缓存默认在 `.cachesDirectory`（系统会在空间紧张时自动清理），250 MB 上限
- Me 页提供"清除聊天缓存"按钮，清空当前用户 SwiftData + Nuke disk cache

### 5.5 多账号 / Logout 缓存隔离

**问题**：同一台手机登出 A、登录 B，如果缓存表没有用户隔离，B 进 App 会先闪出 A 的会话列表 / 消息预览 / 头像缓存——**真实数据泄漏**。

**方案：按 userId 分库**（在 §2.2 `UserSession` 里实现）：
- 每个用户独立的 `ModelContainer`，store URL 形如 `.applicationSupport/EchoIM/users/<userId>/cache.sqlite`
- 不同用户互不可见、零交叉污染——好过"加 ownerUserId 字段 + 每条 query 都过滤"，后者一旦漏写一条 query 就泄漏
- Nuke 没法按用户分目录（其 disk cache 是单例），所以 logout 时**整体清空** `ImagePipeline.shared.cache.removeAll()`

**Logout / Token 失效流程**（时序敏感，`AppContainer.tearDownSession` 已按此顺序实现，见 §2.2）：
1. `AuthRepository.handleUnauthorized()` 触发
2. `await container.tearDownSession()`：
   - **阶段 1**：`ImagePipeline.shared.cache.removeAll()` —— Nuke 与 SwiftData 独立，随时可清
   - **阶段 2**：`container.session = nil` + `await Task.yield()` —— 放掉 `ModelContainer` 引用，让 SwiftData 释放文件句柄
   - **阶段 3**：`FileManager.removeItem(at: .../users/<userId>/)` —— 此时 store 文件无人持有，能真正删干净
3. 清空 Keychain token
4. `RootView` 切回 LoginView

**为什么文件清理必须在 AppContainer 而不是 UserSession 上**：如果 `UserSession.purgeAllCaches()` 里删自己 store 的目录，此时 `self`（即 session）还活着 → `ModelContainer` 还被持有 → SwiftData 还在写 WAL 文件。自己删自己宿主的文件存在时序悖论，只能由外部（AppContainer）在 session 释放**之后**接手。

**注意**：删 store 文件前必须先放掉 ModelContainer 的引用（让 actor 关闭 context），否则 SwiftData 还持有文件句柄。`UserSession` 整个被 nil 出去后再删除，时序最稳。

---

## 6. 图片消息流水线

### 6.1 上传与发送流程

服务端是两步：
1. `POST /api/upload/message-image`（multipart）→ 返回 `{ media_url: "/uploads/messages/..." }`
2. `POST /api/messages`（body JSON）带 `media_url` + `message_type: "image"` + `client_temp_id`

### 6.2 客户端压缩

iOS 系统相册的 HEIC 原图动辄 5-10 MB，必须压缩。**参数对齐服务端**（`server/src/routes/upload.ts` 中 `MESSAGE_IMAGE_CONFIG.maxDimension = 1600`、`outputQuality = 80`，并且服务端 sharp 会用白底 flatten）——客户端必须做相同的白底处理，否则透明 PNG / WebP 转 JPEG 会被 iOS 默认填**黑底**，与服务端结果不一致。

```swift
func compressForUpload(_ image: UIImage) -> (data: Data, width: Int, height: Int)? {
    let maxDim: CGFloat = 1600                       // 与服务端 MESSAGE_IMAGE_CONFIG.maxDimension 一致
    let scale = min(1.0, maxDim / max(image.size.width, image.size.height))
    let targetSize = CGSize(
        width: image.size.width * scale,
        height: image.size.height * scale
    )

    // 关键：opaque = true + 先填白色，再 draw 源图。
    // 这样透明像素会落在白底上，与服务端 sharp.flatten({ r:255, g:255, b:255 }) 行为一致。
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = true
    format.scale = 1                                 // 不要按 @2x/@3x 放大输出
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
    let resized = renderer.image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(origin: .zero, size: targetSize))
        image.draw(in: CGRect(origin: .zero, size: targetSize))
    }

    guard let data = resized.jpegData(compressionQuality: 0.80) else { return nil }   // 与服务端 outputQuality=80 对齐
    return (data, Int(targetSize.width), Int(targetSize.height))
}
```

> 头像压缩同理（先白底 flatten、再 JPEG 编码），方形裁剪在 `image.draw(in:)` 之前用 cropping 实现。

### 6.3 阶段化重试

**问题**：上传成功但发消息失败时，重试**不应**重新上传（浪费流量、服务端会产生孤儿文件）。

```swift
enum ImageSendStage {
    case notStarted                    // 需要从压缩 + 上传开始
    case uploaded(mediaURL: String)    // 已上传，重试时直接调 POST /api/messages
}

// ChatViewModel
var imageSendStages: [String: ImageSendStage] = [:]  // key: clientTempId

func sendImage(_ image: UIImage, clientTempId: String) async {
    imageSendStages[clientTempId] = .notStarted
    await executeImageSend(clientTempId: clientTempId, localImage: image)
}

func retry(clientTempId: String) async {
    guard let stage = imageSendStages[clientTempId] else { return }
    switch stage {
    case .notStarted:
        // 从头来：读 localImage → 压缩 → 上传 → 发消息
    case .uploaded(let mediaURL):
        // 跳过上传，直接发消息
        await postMessage(mediaURL: mediaURL, clientTempId: clientTempId)
    }
}
```

上传成功后立即 `imageSendStages[tempId] = .uploaded(mediaURL)`，然后调发消息接口。

### 6.4 避免 bubble 闪烁

**问题**：发图片时本地立刻用 `Data` 渲染，但服务端确认后如果改用远程 URL 渲染，Nuke 要重新从磁盘/网络加载，会有肉眼可见的闪烁。

**方案**：`LocalMessage.localImageData` 在 VM 存活期间一直保留，`ImageMessageBubble` **优先用 localData**：

```swift
struct ImageMessageBubble: View {
    let localData: Data?
    let remoteURL: URL?

    var body: some View {
        if let data = localData, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFit()
        } else if let url = remoteURL {
            LazyImage(url: url) { state in
                if let image = state.image { image.resizable().scaledToFit() }
                else if state.error != nil { errorPlaceholder }
                else { progressPlaceholder }
            }
        }
    }
}
```

切换聊天页再切回时 `localImageData` 已丢失（VM 重建），fallback 到 Nuke 远程加载，有磁盘缓存命中时也很快。

### 6.5 图片尺寸占位

服务端返回的 Message 不带 width/height，所以收到别人图片时客户端不知道长宽比。**策略**：`LazyImage` 的 placeholder 用 4:3 占位（常见手机照片宽高比），图片加载完后按真实比例重新布局。抖动一次可接受。

---

## 7. WebSocket 生命周期与重连

### 7.1 iOS App 状态与 WS 行为

| App 状态 | WS 行为 |
|----------|---------|
| `.active` | WS 连接，正常收发 |
| `.inactive` | 保持连接（锁屏瞬间、通知中心等过渡态） |
| `.background` | 主动断开（iOS 数秒内会挂起进程，没 APNs 也收不到消息） |

`scenePhase` 监听：

```swift
@Environment(\.scenePhase) private var scenePhase

.onChange(of: scenePhase) { _, newPhase in
    switch newPhase {
    case .active:      wsClient.connectIfNeeded()
    case .background:  wsClient.disconnect(reason: .appBackgrounded)
    default:           break
    }
}
```

### 7.2 网络监控

`NWPathMonitor` 感知 WiFi ↔ 蜂窝切换。网络从不可用变为可用时，重置 `ReconnectPolicy` 退避计数并立即重连。

### 7.3 重连策略

指数退避 + 抖动 + **无限重试**（不设 maxRetries，capped 在 30s 持续尝试）：

```swift
final class ReconnectPolicy {
    private var retryCount = 0
    private let baseDelay: TimeInterval = 1.0
    private let maxDelay: TimeInterval = 30.0

    /// 永不返回 nil——移动网络下"悄悄停止重连"远比"持续慢速重试"危险（高铁、电梯、长隧道）。
    /// 30s 上限的 30s 一次心跳代价可忽略。
    func nextDelay() -> TimeInterval {
        let exp = min(baseDelay * pow(2.0, Double(retryCount)), maxDelay)
        let jitter = Double.random(in: 0...(exp * 0.3))
        retryCount += 1
        return exp + jitter
    }

    func reset() { retryCount = 0 }
}
```

延迟序列：1s → 2s → 4s → 8s → 16s → 30s → 30s → 30s → ...（持续）

**Reset 触发时机**（重置退避到 1s，并立刻发起一次重连，不等当前定时器）：
- 收到 `connection.ready`
- `NWPathMonitor` 报告网络从 unsatisfied → satisfied
- `scenePhase` 从 `.background` → `.active`

这三个外部信号是"重置 + 抢跑一次"——不替代后台 30s 兜底循环，二者并存。

### 7.4 `connection.ready` 握手

服务端完成 Redis SUBSCRIBE 后才发 `connection.ready`。客户端状态机：

```swift
enum WSState {
    case disconnected
    case connecting           // TCP + URLSession 打开中
    case handshaking          // WS 已打开，等 connection.ready
    case ready                // 可收发业务消息
    case reconnecting(in: TimeInterval)
}
```

**约束**：`.handshaking` 状态下不发业务消息；发送队列积攒到 `.ready` 后 flush。握手超时 10 秒也触发重连。

### 7.5 重连后的数据一致性

收到 `connection.ready` 后**按顺序**执行（顺序很重要：会话列表必须早于"草稿 promote"，否则查不到对方刚激活的会话）：

1. **会话列表**：`GET /api/conversations` 刷新 last_message + unread。**先做**这一步是为了让步骤 2、3 能用到最新的会话表
2. **草稿对话 promote**（对齐 Web `client/src/stores/chat.ts:790 promoteActivePeerConversation`）：如果当前打开的 ChatViewModel 处于 draft 态（`conversationId == nil`），扫一遍刚刷的会话列表，找 `peer.id == self.peerId` 的 conversation——找到则把 `conversationId` 回填、走 §5.3 场景 A 拉一次最新。
   - 触发场景：用户停在与 Alice 的草稿聊天页时退后台，Alice 期间发了首条消息；前台回来如果不做这步，输入框还以为没会话、UI 一直停在空白态
3. **当前打开的会话**（已经有 `conversationId`，包括步骤 2 刚 promote 上来的）：走 §5.3 场景 C 的 cursor 翻页——`GET ?after=<newestCachedMessageId>&limit=50` 循环直到返回 < 50（最多 20 页安全阀），逐批 append + 推进 `newestCachedMessageId`
4. **好友申请重拉**（对齐 Web `client/src/hooks/useWebSocket.ts:142`）：`GET /api/friend-requests` 全量刷 `FriendRequestStore`。后台期间收到的 `friend_request.new` / `accepted` / `declined` 事件没在 WS 上重放，只能靠这一次主动拉
5. **Presence 重建**：客户端在收到 `connection.ready` 后立刻 `PresenceStore.clearAll()`，然后被动接收服务端循环推送的多条 `presence.online`（每个在线好友一条；服务端 `ws.ts:sendPresenceSnapshot`）。**服务端没有 `presence.snapshot` 这个事件类型**，不要去监听它

### 7.6 心跳

每 30 秒调用 `URLSessionWebSocketTask.sendPing(pongReceiveHandler:)`，handler 里清掉超时定时器；并发起一个 10 秒超时计时——超时未收到 pong → 视为连接死，主动 close + 走重连。

```swift
func startHeartbeat() {
    heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
        guard let self else { return }
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.handleConnectionDead(reason: .pongTimeout)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeoutWorkItem)

        self.task?.sendPing { [weak self] error in
            timeoutWorkItem.cancel()
            if error != nil { self?.handleConnectionDead(reason: .pingError) }
        }
    }
}
```

### 7.7 与 Web 端的核心差异

| 方面 | Web | iOS |
|------|-----|-----|
| 后台挂起 | Tab 不活跃时 socket 仍在 | 数秒内被系统关闭 |
| 网络切换 | 浏览器透明处理 | 需 `NWPathMonitor` 主动感知 |
| 重连触发 | `onclose` | `onclose` + `scenePhase` + 网络恢复 |

### 7.8 服务端推送的 WS 事件全集

`WSEvent` 必须 decode 下面所有类型；不要漏 `friend_request.*`，否则好友请求收发都得手动刷新。

| 事件 | 方向 | payload | 用途 |
|------|------|---------|------|
| `connection.ready` | S → C | (无) | Redis SUBSCRIBE 完成、可发业务消息 |
| `message.new` | S → C | `Message`（发送者那份带 `client_temp_id`） | 实时消息送达 / 自己发送的回声 |
| `conversation.updated` | S → 自己 | `{ conversation_id, last_read_message_id }` | 多设备已读游标同步 |
| `typing.start` / `typing.stop` | S → 对方 | `{ conversation_id, user_id }` | 输入指示 |
| `presence.online` / `presence.offline` | S → 在线好友 | `{ user_id }` | 好友上下线；连接就绪后服务端会循环 push 一遍当前在线好友（**不是单条 snapshot**） |
| `friend_request.new` | S → 双方 | `FriendRequest` | 收到 / 发送了好友申请 |
| `friend_request.accepted` | S → 双方 | `FriendRequest` | 申请被接受（双方都收到） |
| `friend_request.declined` | S → 双方 | `FriendRequest` | 申请被拒绝 |

`friend_request.*` 在双向都推：判断方向用 `payload.sender_id == currentUserId`（参考 `client/src/hooks/useWebSocket.ts:62-86`）。

**客户端发的 WS 事件**（仅这两种）：`typing.start` / `typing.stop`，payload `{ type, conversation_id }`。其它事件全部走 REST。

---

## 8. 交付阶段（P1-P8）

每阶段都交付一个能运行、能演示的增量。

### P1：工程脚手架 + 登录 / 注册

**交付**：依赖引入（KeychainAccess、Nuke、NukeUI） / 基础目录结构 / `APIClient` + `APIError` / `AuthRepository`（`login` + `register`） / `KeychainTokenStore` / `LoginView` + `LoginViewModel` / `RegisterView` + `RegisterViewModel` / Login 与 Register 互相跳转 / 占位首页（用户名 + 登出）

**注册流程对齐 Web**（参考 `client/src/pages/RegisterPage.tsx`）：
- 字段：`inviteCode`（必填）、`username`（≥ 3）、`email`、`password`（≥ 8）。客户端做最小长度校验 + 邮箱格式校验，提交前给即时反馈
- API：`POST /auth/register` body `{ username, email, password, inviteCode }`，成功返回 `{ token, user }`，与 login 走同一套写 Keychain + 进首页的成功路径
- 错误映射：
  - 403 `Invalid invite code` → 标红 inviteCode 字段 + toast "邀请码无效"
  - 409 `Email already in use` → 标红 email 字段
  - 409 `Username already taken` → 标红 username 字段
  - 400 字段校验失败 → 字段下方显示对应文案
- 不做"已登录用户访问注册页则重定向"——iOS 没有 deeplink 到 Register 的入口，未登录态从 LoginView 进，已登录态根本看不到 RegisterView

**测试**：注册成功直接进首页；用过的邮箱 / 用户名给字段级错误；错的邀请码立刻提示；登录成功 / 登出 Keychain 清空 / 错误密码 toast；Login ↔ Register 互跳保留输入态可选（不强制）。

**依赖**：无。

### P2：好友列表 + 会话列表

**交付**：`UserRepository` / `FriendRepository` / `ConversationRepository` / TabView（Chats / Contacts / Me） / 好友列表 + 好友请求入口 / 会话列表（头像、display_name、last_message 预览、unread 角标） / 下拉刷新 / 头像用 `LazyImage`。

**测试**：互加好友流程；会话列表按 `last_message_at` 倒序；未读数正确；头像缓存命中。

**依赖**：P1。

### P3：文字消息 + 实时 WebSocket

**交付**：`WebSocketClient`（第 7 节设计） / `WSEvent` decode / `MessageRepository` / `ChatView` + `ChatViewModel`（第 4 节设计） / 乐观发送（`clientTempId` 合并） / 失败重试 / 上滑分页 / 进入会话标已读 / `ChatsList` 接 WS 更新。

**测试**：秒级送达；断网 → 重试成功；杀后台回前台能补拉；上滑分页滚动无跳动。

**依赖**：P1, P2。

### P4：本地持久化（SwiftData 缓存）

**交付**：`@Model CachedMessage` + `@Model ConversationMeta` / 缓存落盘在 `.applicationSupport` + 排除备份 / `ChatViewModel` 改造为第 5 节的连续后缀不变式 / `ConversationListViewModel` 先读 meta 再刷新 / Me 页"清除聊天缓存"按钮。

**测试**：杀 App 再打开零等待；断网下缓存会话仍可滑动；别设备发消息后回到本设备能正确看到；清缓存按钮清空 SwiftData + Nuke。

**依赖**：P3。

### P5：图片消息

**交付**：`UploadRepository.uploadMessageImage` / `ImageCompressor`（1600px / JPEG 0.80，对齐服务端 `MESSAGE_IMAGE_CONFIG`） / `PhotosPicker` 接入输入栏 / 第 6 节的阶段化重试（`ImageSendStage`） / `ImageMessageBubble` localData 优先 / 全屏预览（pinch/zoom） / `ChatsList` 显示 `[图片]` / 收到对方图片走 Nuke 加载。

**测试**：发图全链路成功；上传成功但发消息失败时重试不重新上传；杀 App 后图片仍能从缓存加载；发送后切出切回不闪烁。

**依赖**：P3, P4。

### P6：Presence + Typing

**交付**：`PresenceStore`（处理 `presence.online` / `presence.offline`，重连收到 `connection.ready` 后先 `clearAll()`，再被动收服务端循环 push 的多条 `presence.online` 重建集合） / 好友列表 + 会话列表 + 聊天页顶部在线圆点 / `TypingStore` 带 5 秒安全定时器 / 聊天页顶部"正在输入..." / 本端 debounce 发 `typing.start` / `typing.stop`。

**测试**：A 登入登出 B 能看到；A 打字 B 看到"正在输入..."，A 停 3 秒自动消失；A 发送后本端立即清 typing；重连后 PresenceStore 状态与实际在线好友一致（验证 clearAll + 循环 online 重建路径）。

**依赖**：P3。

### P7：Profile 编辑 + 头像上传

**交付**：Me 页 editable display_name + 头像 / `UploadRepository.uploadAvatar`（400px 方形裁剪 + JPEG 0.80，对齐服务端 `AVATAR_CONFIG`） / `UserRepository.updateProfile` / profile 修改后同步 auth store / 别人 profile 只读展示（从聊天页顶部头像进入）。

**测试**：改名后 UI 同步；改头像对方能看到新头像；头像文件 < 200 KB。

**依赖**：P1。

### P8：打磨 + 测试 + Dark Mode

**交付**：
- 所有界面 Dark Mode 检查
- 加载/空/错误态统一（spinner / empty / retry）
- 键盘处理（输入框上浮、滚动跟随）
- 触觉反馈（发消息、好友通过）
- **Swift Testing 单元测试**：
  - `ChatViewModel` gap detection 三场景
  - `ImageSendStage` 重试跳过
  - `ReconnectPolicy` 退避序列
  - WS 事件 decode
- **XCUITest golden path**：登录 → 会话列表 → 发文字 → 发图片
- 内存泄漏检查（Instruments）
- i18n：`Localizable.strings` zh / en

**测试**：Swift Testing 全通过；XCUITest golden path 通过；真机跑一遍主要流程；Dark Mode 无视觉瑕疵；聊天页反复进出内存稳定。

**依赖**：P1-P7。

### 依赖关系图

```
P1 (脚手架+登录)
 ├─→ P2 (好友+会话列表)
 │    └─→ P3 (文字消息+WS) ──┬─→ P4 (SwiftData 缓存) ──┐
 │                          ├─→ P6 (Presence+Typing)   │
 │                          │                          │
 │                          └──────────────────────────┼─→ P5 (图片消息)
 │                                                     │
 └─→ P7 (Profile 编辑)                                 │
                                                       │
                                      所有阶段 ───→ P8 (打磨+测试)
```

P5 依赖 P4（图片消息缓存要对齐 gap 检测）。P6 与 P4 可并行。

### 阶段"可演示价值"

| 阶段 | 能演示的价值 |
|------|-------------|
| P1 | 登录进 App |
| P2 | 看到好友、会话列表（静态） |
| P3 | **真实聊天**（文字 + 实时） |
| P4 | 离线打开 App 能看到历史 |
| P5 | 发图片 |
| P6 | 看到对方在线 / 正在输入 |
| P7 | 改名片 |
| P8 | 可以发给朋友试玩 |

---

## 9. 测试策略

- **Swift Testing**（单元）：ViewModel 业务逻辑（gap detection、ImageSendStage 状态机、ReconnectPolicy）、WS 事件 decode、日期解析
- **XCUITest**（UI）：golden path（登录 → 发消息 → 发图片）
- **手工**：真机跑 Dark Mode、多设备互发、断网重连、后台回前台
- **Web 端已有 Playwright E2E**：iOS 端不重复覆盖已由服务端测试保证的业务规则

Web 客户端侧没有单测，iOS 端不要求每个文件都写；优先覆盖"容易出 bug"的纯逻辑。

---

## 10. 已知限制与未来工作

**作品集范围内不做，但会留扩展点**：
- **APNs 推送**：后台期间不收消息。未来加 APNs 时，WS 断开后由服务端推 push，用户点击后恢复 WS。
- **群聊**：数据库 `conversation_members` 已经是多对多，但业务层假设 1-on-1；改群聊需要服务端 + 客户端同步改动。
- **消息搜索**：SwiftData 已落盘消息，后续可加全文索引（`@Attribute(.externalStorage)` + SQLite FTS）。
- **消息撤回/删除**：服务端尚未支持，暂不做。
- **iPad 适配**：UI 用 `NavigationSplitView` 重写。

**已知限制**：
- 服务端返回的图片 Message 不带 width/height，发送方压缩时能拿到（存 Message 原始响应），但接收方只能靠 Nuke 加载完重新布局，首次有一次抖动
- 重连补拉的 20 页安全阀触顶后，更早的"漏掉"消息要靠用户上滑分页主动拉回——作品集场景可接受
- **JWT 过期不做静默续签**：服务端 token 7 天有效，到期后 REST 401 或 WS upgrade 401 都触发 `AuthRepository.handleUnauthorized()`：`await container.tearDownSession()`（按 §5.5 清当前用户 SwiftData + Nuke）→ 清空 Keychain → 通知 `RootView` 切回 LoginView → 弹 toast"登录已过期，请重新登录"
- **WS 401 vs 网络断的区分**：`URLSessionWebSocketTask` 闭包式 init 拿不到 HTTP 升级响应，必须用 `URLSessionWebSocketDelegate`：

  ```swift
  final class WebSocketClient: NSObject, URLSessionWebSocketDelegate, URLSessionTaskDelegate {
      func urlSession(_ session: URLSession,
                      webSocketTask: URLSessionWebSocketTask,
                      didOpenWithProtocol protocol: String?) {
          // upgrade 成功，等服务端 connection.ready
      }

      func urlSession(_ session: URLSession,
                      task: URLSessionTask,
                      didCompleteWithError error: Error?) {
          if let http = task.response as? HTTPURLResponse, http.statusCode == 401 {
              Task { @MainActor in await authRepository.handleUnauthorized() }
              return                                  // 不重连
          }
          scheduleReconnect()                         // 其它失败 → 走 §7.3 退避
      }
  }
  ```

  关键点：`task.response` 是 `HTTPURLResponse`，401 在 `didCompleteWithError` 时一定能拿到（服务端 `ws.ts:174` 的 `socket.write('HTTP/1.1 401 ...')` 就是个完整 HTTP 响应）。**不要**用 "没收到 connection.ready 就当 401" 这种间接判断——握手超时、Redis 慢都会导致同样表现，会误清登录态

---

## 11. 服务端契约依赖

iOS 端实现需要服务端做的小调整（不影响 Web 端，向后兼容）：

### 11.1 `GET /api/conversations/:id/messages` 加 `limit` 参数

**动机**：iOS 上滑分页采用"本地优先 + 远端补缺"策略（§5.3），本地命中 N 条时只需向服务端要 `(PAGE_SIZE - N)` 条；当前服务端 `LIMIT` 写死 50，无 `?limit=` 入参。

**改动**（`server/src/routes/conversations.ts`）：
- querystring schema 增加 `limit: { type: 'integer', minimum: 1, maximum: 50, default: 50 }`
- SQL 把 `LIMIT 50` 改成 `LIMIT $3`，参数列表追加 `limit ?? 50`

**向后兼容**：Web 端不传 `limit` 时走 default 50，行为不变。

---

## 附：关键约定速查

- **乐观发送去重 key**：`clientTempId`（客户端生成，服务端原样回传给**发送者**的 WS echo 和 REST 响应；不持久化到数据库）
- **分页 cursor**：全局 SERIAL ID（不是 timestamp），`?before=<id>&limit=<N>` / `?after=<id>&limit=<N>`，`limit` 默认 50、上限 50
- **已读游标**：`last_read_message_id`（服务端 `GREATEST(old, new)` 单调递增）
- **对话自动创建**：两好友首发消息时（服务端 advisory lock）
- **消息类型**：`message_type: "text" | "image"`，DB CHECK 约束保证 text 必填 body / image 必填 media_url
- **WS 连接就绪信号**：`connection.ready`（Redis SUBSCRIBE 完成后）
- **只发给自己的 WS 事件**：`conversation.updated`（多设备已读同步，对方看不到"已读回执"）；`message.new` 的 `client_temp_id` 字段也只有发送者那份带
- **`media_url` 不要客户端拼**：必须用 `POST /api/upload/message-image` 返回的字符串原样回传给 `POST /api/messages`。服务端 `messages.ts` 会校验路径形如 `^/uploads/messages/{senderId}-\d{10,16}\.jpg$`，不匹配直接 400
- **图片压缩参数对齐服务端**：消息图 1600px / JPEG 0.80（`MESSAGE_IMAGE_CONFIG`）、头像 400px / JPEG 0.80（`AVATAR_CONFIG`）。客户端压完即接近终态，避免服务端二次有损缩放
