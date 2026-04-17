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
│   │   ├── AuthViewModel.swift
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

```swift
@MainActor
final class AppContainer {
    let tokenStore: KeychainTokenStore
    let apiClient: APIClient
    let wsClient: WebSocketClient
    let swiftDataContext: ModelContext
    let presenceStore = PresenceStore()
    let typingStore = TypingStore()

    init(tokenStore: KeychainTokenStore,
         apiClient: APIClient,
         wsClient: WebSocketClient,
         swiftDataContext: ModelContext) {
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        self.wsClient = wsClient
        self.swiftDataContext = swiftDataContext
    }

    func makeAuthRepository() -> AuthRepository {
        AuthRepositoryImpl(api: apiClient, tokenStore: tokenStore)
    }
    func makeMessageRepository() -> MessageRepository { ... }
    func makeChatViewModel(conversationId: Int) -> ChatViewModel { ... }
}
```

`RootView` 从 `@Environment` 拿到 `AppContainer`，调 factory 方法构造 ViewModel。

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

struct Conversation: Codable, Identifiable {
    let id: Int
    let createdAt: Date
    let peer: User
    let lastMessageBody: String?
    let lastMessageType: String?        // "text" | "image"
    let lastMessageAt: Date?
    let lastReadMessageId: Int?
    let unreadCount: Int
}

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
    private let conversationId: Int
    private let peerId: Int

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

**场景 C：有缓存，补拉返回满 50 条（gap wipe）**
- 如果 `GET ?after=<newestCachedMessageId>` 返回正好 50 条（上限），说明中间可能有更多消息未被带回
- **保守策略：擦除整个会话缓存，退回场景 A**。`conversationId` 下所有 `CachedMessage` 删除，`ConversationMeta` 的 `oldestCached/newestCached` 置 nil，重新拉最新 50 条
- 为什么不尝试继续补拉？因为服务端 SERIAL ID 是全局的，你不知道"后面还有多少条属于本会话"；反复补拉 vs 一次擦除+重来，后者代码简单且错误面更小

**上滑加载历史消息**：
- 先查 SwiftData：`messageId < oldestCachedMessageId` 的消息，按 ID 倒序取 50
- 如果本地够 50 条 → 直接用本地
- 如果不够 → 用本地最老的（或 `oldestCachedMessageId`）作为 cursor 调 `GET ?before=<id>`
- 返回的条目落盘，更新 `oldestCachedMessageId` 为返回中的最小 ID
- **不变式保持**：`before` 查询语义 "id < cursor ORDER BY id DESC"，新拿到的紧接在旧缓存之前

**WS 实时消息到达**：
- `message.new` 事件：如果 `message.id == newestCachedMessageId + 1`，或者"发送者就是自己"（刚刚乐观发的），直接 append，更新 `newestCachedMessageId`
- 如果 `message.id > newestCachedMessageId + 1` 且非自己发的 → 中间有跳号，但因为 SERIAL 全局递增，跳号几乎一定是别的会话造成的，不是 gap；直接 append 即可
- 判断 gap 只发生在"重连后补拉"的场景，不在单条 WS 推送时判断

### 5.4 存储位置

- SwiftData 默认 store 放 `.applicationSupport`（**不是** `.documentDirectory`，文档目录会出现在"文件"App 里、会被 iCloud 备份，不适合缓存）
- 设置 `NSURLIsExcludedFromBackupKey = true`，避免 iCloud 备份占用用户空间
- Nuke 磁盘缓存默认在 `.cachesDirectory`（系统会在空间紧张时自动清理），250 MB 上限
- Me 页提供"清除聊天缓存"按钮，清空 SwiftData + Nuke disk cache

---

## 6. 图片消息流水线

### 6.1 上传与发送流程

服务端是两步：
1. `POST /api/upload/message-image`（multipart）→ 返回 `{ media_url: "/uploads/messages/..." }`
2. `POST /api/messages`（body JSON）带 `media_url` + `message_type: "image"` + `client_temp_id`

### 6.2 客户端压缩

iOS 系统相册的 HEIC 原图动辄 5-10 MB，必须压缩：

```swift
func compressForUpload(_ image: UIImage) -> (data: Data, width: Int, height: Int)? {
    let maxDim: CGFloat = 1920
    let scale = min(1.0, maxDim / max(image.size.width, image.size.height))
    let targetSize = CGSize(
        width: image.size.width * scale,
        height: image.size.height * scale
    )
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let resized = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
    return (data, Int(targetSize.width), Int(targetSize.height))
}
```

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

指数退避 + 抖动：

```swift
final class ReconnectPolicy {
    private var retryCount = 0
    private let maxRetries = 10
    private let baseDelay: TimeInterval = 1.0
    private let maxDelay: TimeInterval = 30.0

    func nextDelay() -> TimeInterval? {
        guard retryCount < maxRetries else { return nil }
        let exp = min(baseDelay * pow(2.0, Double(retryCount)), maxDelay)
        let jitter = Double.random(in: 0...(exp * 0.3))
        retryCount += 1
        return exp + jitter
    }

    func reset() { retryCount = 0 }
}
```

延迟序列：1s → 2s → 4s → 8s → 16s → 30s → 30s → ...
Reset 触发时机：收到 `connection.ready`；`NetworkMonitor` 报告网络恢复。

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

收到 `connection.ready` 后：
1. **当前打开的会话**：`GET /api/conversations/:id/messages?after=<newestCachedMessageId>`
   - 返回 < 50 条 → append 进缓存
   - 返回满 50 条 → 走第 5 节的 gap wipe：擦除缓存 + 重拉最新 50
2. **会话列表**：重新 `GET /api/conversations` 刷新 last_message + unread
3. **Presence 快照**：服务端主动推 `presence.snapshot`，客户端覆盖本地状态

### 7.6 心跳

`URLSessionWebSocketTask.sendPing()` 每 30 秒一次。10 秒内没收到 pong → 视为连接死，重连。

### 7.7 与 Web 端的核心差异

| 方面 | Web | iOS |
|------|-----|-----|
| 后台挂起 | Tab 不活跃时 socket 仍在 | 数秒内被系统关闭 |
| 网络切换 | 浏览器透明处理 | 需 `NWPathMonitor` 主动感知 |
| 重连触发 | `onclose` | `onclose` + `scenePhase` + 网络恢复 |

---

## 8. 交付阶段（P1-P8）

每阶段都交付一个能运行、能演示的增量。

### P1：工程脚手架 + 登录

**交付**：依赖引入（KeychainAccess、Nuke、NukeUI） / 基础目录结构 / `APIClient` + `APIError` / `AuthRepository` / `KeychainTokenStore` / `LoginView` + `LoginViewModel` / 占位首页（用户名 + 登出）

**测试**：登录成功、登出后 Keychain 清空、错误密码显示 toast。

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

**交付**：`UploadRepository.uploadMessageImage` / `ImageCompressor`（1920px / JPEG 0.85） / `PhotosPicker` 接入输入栏 / 第 6 节的阶段化重试（`ImageSendStage`） / `ImageMessageBubble` localData 优先 / 全屏预览（pinch/zoom） / `ChatsList` 显示 `[图片]` / 收到对方图片走 Nuke 加载。

**测试**：发图全链路成功；上传成功但发消息失败时重试不重新上传；杀 App 后图片仍能从缓存加载；发送后切出切回不闪烁。

**依赖**：P3, P4。

### P6：Presence + Typing

**交付**：`PresenceStore`（处理 `presence.snapshot` / `presence.online` / `presence.offline`） / 好友列表 + 会话列表 + 聊天页顶部在线圆点 / `TypingStore` 带 5 秒安全定时器 / 聊天页顶部"正在输入..." / 本端 debounce 发 `typing.start` / `typing.stop`。

**测试**：A 登入登出 B 能看到；A 打字 B 看到"正在输入..."，A 停 3 秒自动消失；A 发送后本端立即清 typing；重连后 `presence.snapshot` 覆盖正确。

**依赖**：P3。

### P7：Profile 编辑 + 头像上传

**交付**：Me 页 editable display_name + 头像 / `UploadRepository.uploadAvatar`（512px 方形裁剪 + JPEG 0.85） / `UserRepository.updateProfile` / profile 修改后同步 auth store / 别人 profile 只读展示（从聊天页顶部头像进入）。

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
- 重连后满 50 条 gap wipe 是"保守且简单"的策略，不是"最小流量"；作品集场景可接受

---

## 附：关键约定速查

- **乐观发送去重 key**：`clientTempId`（客户端生成，服务端原样回传给**发送者**的 WS echo 和 REST 响应；不持久化到数据库）
- **分页 cursor**：全局 SERIAL ID（不是 timestamp），`?before=<id>` / `?after=<id>`
- **已读游标**：`last_read_message_id`（服务端 `GREATEST(old, new)` 单调递增）
- **对话自动创建**：两好友首发消息时（服务端 advisory lock）
- **消息类型**：`message_type: "text" | "image"`，DB CHECK 约束保证 text 必填 body / image 必填 media_url
- **WS 连接就绪信号**：`connection.ready`（Redis SUBSCRIBE 完成后）
- **只发给自己的 WS 事件**：`conversation.updated`（多设备已读同步，对方看不到"已读回执"）；`message.new` 的 `client_temp_id` 字段也只有发送者那份带
