# iOS P3 实施计划：文字消息 + 实时 WebSocket

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ios-app/` 从 P2 的"三 Tab 主界面 + 好友/会话/资料列表（静态）"推进到"能真实地和好友互发文字消息，实时送达，断网可重试，上滑翻页，进入会话自动标已读"——对应设计文档第 8 节的 P3。

**Architecture:** 引入 `WebSocketClient`（`URLSessionWebSocketTask` + `URLSessionWebSocketDelegate`），在 `AppContainer` 生命周期上与 `currentUser` 联动（登录连、登出断、401 踢）。`ChatViewModel` 管理单个会话的消息状态，走乐观发送 + `clientTempId` 合并 + 失败重试；`ConversationsListViewModel` 订阅 WS 事件实时刷新会话预览和未读数。**本阶段不接 SwiftData（P4）、不做图片消息（P5）、不接 presence/typing（P6）、不接 friend_request.\* 的增量处理**（P6+，P3 只保证解码不崩，ContactsView 继续用 P2 的 `.refreshable`）。

**Tech Stack:** SwiftUI、Swift Concurrency、`URLSessionWebSocketTask`、`URLSessionWebSocketDelegate`、`Network.framework`（`NWPathMonitor`）、Swift Testing、XCUITest。

**TDD 适用范围（与 P1/P2 一致）：**
- **纯逻辑 → TDD**：`Message` 解码、`WSEvent` 解码、`ReconnectPolicy` 退避序列、`ChatViewModel` 的状态机（乐观发送、WS 合并、分页游标、已读推进）、`MessageRepository` endpoint/method/querystring。
- **View / WS integration → 编译 + 模拟器手工清单**：`WebSocketClient` 与真实 URLSession 的交互、`ChatView` SwiftUI、导航、scenePhase 联动走手工 + XCUITest smoke。

**服务端契约：** 本阶段依赖的接口**全部已存在**，不需要服务端改动：
- `POST /api/messages` body `{ recipient_id, body, message_type?, client_temp_id? }`（`server/src/routes/messages.ts:7`）
- `GET /api/conversations/:id/messages?before=<id>` / `?after=<id>`（`server/src/routes/conversations.ts:36`）
- `PUT /api/conversations/:id/read` body `{ last_read_message_id }`（`server/src/routes/conversations.ts:91`）
- `WS /ws?token=<jwt>`（`server/src/plugins/ws.ts:159`）；服务端事件全集见设计文档 §7.8。

**不在 P3 范围（明确延后）：**
- `?limit=` querystring 参数 → 设计 §11.1，属于 P4 的契约改动（本阶段始终走默认 50 条）
- **Gap detection / 连续后缀不变式** → 设计 §5.2，需要 SwiftData，属于 P4
- **图片消息 + 压缩 + 两步上传** → P5
- **Presence + Typing** → P6；WebSocketClient 只需要**能解码** `typing.*` / `presence.*` 事件（不崩 decode），不需要真正做 UI 响应；发送方向的 `typing.start/stop` P3 不发
- **friend_request.\* 增量处理** → 本阶段只解码不接入；ContactsView 继续保留 P2 的被动刷新（`.task` + `.refreshable`）
- **UserSession 拆出** → 设计 §2.2，因为 ModelContainer 的所有权需要才必要，P4 做；P3 把 `WebSocketClient` 作为 `AppContainer` 的 `var` 持有即可
- **前台恢复路径 `scenePhase` 联动**：P3 引入（§7.5 是聊天必需的 reconnect 路径），但仅覆盖 WS 重连；"前台刷新 `currentUser`/好友申请/presence 重建"的完整流程等 P6

**已知妥协（`retry` 重复投递风险）：** `client_temp_id` 不持久化到服务端；网络超时后客户端重试若服务端其实已处理第一条，会造成服务端重复行（对方收到两条同文本消息）。作品集范围可接受，留作已知限制。未来接 APNs / 更强去重时再处理。

---

## 开发环境前提

沿用 P1/P2（不重复）。约定命令：

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

**后端前提：** 本阶段联调需要后端在跑（`docker compose up` 或 `npm --prefix server run dev`）。至少两个互为好友的测试用户（A、B），且两账号互为 `status = 'accepted'`（可用 P2 的联系人流程建立）。iOS 模拟器直接连 `http://localhost:3000`；WS 连 `ws://localhost:3000/ws?token=<jwt>`。模拟器和宿主机共享 localhost，不需要特殊 host 映射。

---

## 文件结构（P3 新增 / 修改）

本阶段**不**触及的目录：`ios-app/EchoIM/Core/Storage/Models/`（P4）、`ios-app/EchoIM/Features/Shared/Stores/` 里的 `PresenceStore` / `TypingStore`（P6）、`ios-app/EchoIM/Core/Utilities/ImageCompressor.swift`（P5）。

```
ios-app/EchoIM/
├── App/
│   ├── AppContainer.swift                        // MODIFY：持有 WebSocketClient；handleLoginSuccess/logout/handleUnauthorized 三个钩子统一驱动 WS 连/断；新增 tearDownSession（P3 版：断 WS + 清登录态）
│   └── RootView.swift                            // MODIFY：已登录分支 onChange(scenePhase)，前台 connectIfNeeded / 后台 disconnect
├── Core/
│   ├── Networking/
│   │   ├── Models/
│   │   │   ├── Message.swift                     // NEW：从 APIClient.swift 搬出来；字段不变
│   │   │   └── WSEvent.swift                     // NEW：顶层 enum；能解码所有设计 §7.8 事件，不崩
│   │   ├── APIClient.swift                       // MODIFY：删除 Message 定义（已搬家）
│   │   ├── Endpoints.swift                       // MODIFY：追加 Messages / Conversations.messages(:convId:) / webSocketURL(token:) helper
│   │   ├── WebSocketClient.swift                 // NEW：URLSessionWebSocketTask 封装 + delegate + 状态机 + 重连 + 心跳
│   │   └── ReconnectPolicy.swift                 // NEW：指数退避 + jitter；纯值类型
├── Features/
│   ├── Conversations/
│   │   ├── ConversationsListViewModel.swift      // MODIFY：订阅 WS，message.new / conversation.updated 增量刷新
│   │   └── ConversationsListView.swift           // MODIFY：NavigationLink(value: conversation) 进入 ChatView
│   ├── Contacts/
│   │   └── ContactsView.swift                    // MODIFY：点击好友 row 进入 ChatView（draft 模式）
│   └── Chat/
│       ├── ChatRoute.swift                       // NEW：enum ChatRoute { case conversation(Conversation), case peer(UserProfile) } — 支持已有会话与草稿
│       ├── ChatViewModel.swift                   // NEW：单会话状态机（加载/分页/乐观发送/合并/重试/WS 订阅/markRead）
│       ├── ChatView.swift                        // NEW：消息列表 + 输入栏 + 上滑加载更多
│       ├── MessageBubble.swift                   // NEW：文字气泡（pending/sent/failed 三态 + 失败重试）
│       └── MessageRepository.swift               // NEW：list(before/after) + sendText

ios-app/EchoIMTests/                              // 追加文件
├── MessageDecodingTests.swift                    // NEW：Message 解码（包含 client_temp_id / 无 client_temp_id 两种）
├── WSEventDecodingTests.swift                    // NEW：业务事件 + unknown 解码；connection.ready 由 WebSocketClient 内部消化
├── ReconnectPolicyTests.swift                    // NEW：退避序列 + reset + jitter 上下界
├── MessageRepositoryTests.swift                  // NEW：list(before/after) endpoint + send text body + snake_case
├── ChatViewModelLoadTests.swift                  // NEW：加载最新 / 上滑分页 / 空态 / 错误分支
├── ChatViewModelSendTests.swift                  // NEW：乐观发送 + 合并 + 失败态 + 重试（含"服务端 echo 比 REST 先到"的竞态）
├── ChatViewModelWSTests.swift                    // NEW：message.new / conversation.updated / draft promote 的合并
└── ChatViewModelReadTests.swift                  // NEW：onAppear markRead + 仅推进不回退 + 重复短路

ios-app/EchoIMUITests/
└── ChatSmokeTests.swift                          // NEW：登录 → 会话列表 → 进入 A↔B 会话 → 发一条 → 列表预览更新
```

---

## Task 1：Message 搬家 + WSEvent 解码模型

**Files:**
- Create: `ios-app/EchoIM/Core/Networking/Models/Message.swift`
- Create: `ios-app/EchoIM/Core/Networking/Models/WSEvent.swift`
- Modify: `ios-app/EchoIM/Core/Networking/APIClient.swift`
- Test: `ios-app/EchoIMTests/MessageDecodingTests.swift`
- Test: `ios-app/EchoIMTests/WSEventDecodingTests.swift`

**动机：** P2 建立的约定是"每个模型独立文件"（UserProfile / Friend / FriendRequest / Conversation），但 `Message` 还赖在 `APIClient.swift` 里。这一步顺手搬家，并把 `WSEvent` 放到同目录，方便后续 Chat 相关改动一次性看到。`WSEvent` 必须能解码设计 §7.8 全集——漏掉任何一个，WS 收到未识别事件时解码抛错、`handleReceive` 就会把整条连接判死。

**关于 `connection.ready`**：它不是业务事件，是握手信号，**不放进 `WSEvent` 枚举**——`WebSocketClient` 内部消化（见 Task 4），不分发给订阅者。

- [ ] **Step 1：写 Message 解码失败测试**

`ios-app/EchoIMTests/MessageDecodingTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@Suite("Message decoding")
struct MessageDecodingTests {
    @Test func decodesTextMessageWithClientTempId() throws {
        let json = """
        {
          "id": 101, "conversation_id": 5, "sender_id": 9,
          "body": "hi", "message_type": "text", "media_url": null,
          "created_at": "2026-04-20T10:00:00.123Z",
          "client_temp_id": "pending-1234-1"
        }
        """.data(using: .utf8)!
        let m = try APIClient.jsonDecoder.decode(Message.self, from: json)
        #expect(m.id == 101)
        #expect(m.conversationId == 5)
        #expect(m.senderId == 9)
        #expect(m.body == "hi")
        #expect(m.messageType == "text")
        #expect(m.clientTempId == "pending-1234-1")
    }

    @Test func decodesMessageWithoutClientTempId() throws {
        let json = """
        {
          "id": 102, "conversation_id": 5, "sender_id": 3,
          "body": "yo", "message_type": "text", "media_url": null,
          "created_at": "2026-04-20T10:01:00.000Z"
        }
        """.data(using: .utf8)!
        let m = try APIClient.jsonDecoder.decode(Message.self, from: json)
        #expect(m.clientTempId == nil)
    }

    @Test func decodesImageMessage() throws {
        let json = """
        {
          "id": 103, "conversation_id": 5, "sender_id": 9,
          "body": null, "message_type": "image",
          "media_url": "/uploads/messages/9-1712345678.jpg",
          "created_at": "2026-04-20T10:02:00.000Z"
        }
        """.data(using: .utf8)!
        let m = try APIClient.jsonDecoder.decode(Message.self, from: json)
        #expect(m.body == nil)
        #expect(m.messageType == "image")
        #expect(m.mediaUrl == "/uploads/messages/9-1712345678.jpg")
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`Message` 在 `Models/` 目录下不存在——编译失败的是新测试文件的 `import` 定位（`Message` 已经在 APIClient.swift 定义，所以第一次跑其实会过；这步让测试先跑起来，下一步再做搬家）。如果测试直接绿，也没关系——Step 3 的搬家是纯重构，不会改变行为。

- [ ] **Step 3：搬家 Message**

创建 `ios-app/EchoIM/Core/Networking/Models/Message.swift`：

```swift
import Foundation

/// 一条消息（服务端原样）。`clientTempId` 仅对发送者自己的那条存在，
/// 用于乐观发送去重（见 ChatViewModel.send）；不持久化。
struct Message: Codable, Identifiable, Equatable, Sendable, Hashable {
    let id: Int
    let conversationId: Int
    let senderId: Int
    let body: String?
    let messageType: String
    let mediaUrl: String?
    let createdAt: Date
    let clientTempId: String?
}
```

编辑 `ios-app/EchoIM/Core/Networking/APIClient.swift`，**删除**顶部的 `struct Message: ...` 定义（行 3-12）。保留 `AuthenticatedUser` / `AuthResponse` / `EmptyResponse` 等。

- [ ] **Step 4：写 WSEvent 解码失败测试**

`ios-app/EchoIMTests/WSEventDecodingTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@Suite("WSEvent decoding")
struct WSEventDecodingTests {
    private func decode(_ json: String) throws -> WSEvent {
        try APIClient.jsonDecoder.decode(WSEvent.self, from: json.data(using: .utf8)!)
    }

    @Test func decodesMessageNew() throws {
        let ev = try decode("""
        { "type": "message.new", "payload": {
            "id": 200, "conversation_id": 7, "sender_id": 3,
            "body": "hey", "message_type": "text", "media_url": null,
            "created_at": "2026-04-20T09:00:00.000Z"
          } }
        """)
        guard case .messageNew(let msg) = ev else {
            Issue.record("expected .messageNew")
            return
        }
        #expect(msg.id == 200)
        #expect(msg.body == "hey")
    }

    @Test func decodesMessageNewWithClientTempId() throws {
        let ev = try decode("""
        { "type": "message.new", "payload": {
            "id": 201, "conversation_id": 7, "sender_id": 9,
            "body": "echo", "message_type": "text", "media_url": null,
            "created_at": "2026-04-20T09:00:10.000Z",
            "client_temp_id": "pending-abc"
          } }
        """)
        guard case .messageNew(let msg) = ev else {
            Issue.record("expected .messageNew")
            return
        }
        #expect(msg.clientTempId == "pending-abc")
    }

    @Test func decodesConversationUpdated() throws {
        let ev = try decode("""
        { "type": "conversation.updated",
          "payload": { "conversation_id": 7, "last_read_message_id": 199 } }
        """)
        guard case .conversationUpdated(let p) = ev else {
            Issue.record("expected .conversationUpdated")
            return
        }
        #expect(p.conversationId == 7)
        #expect(p.lastReadMessageId == 199)
    }

    @Test func decodesTypingStart() throws {
        let ev = try decode("""
        { "type": "typing.start",
          "payload": { "conversation_id": 7, "user_id": 3 } }
        """)
        if case .typingStart(let p) = ev {
            #expect(p.conversationId == 7)
            #expect(p.userId == 3)
        } else {
            Issue.record("expected .typingStart")
        }
    }

    @Test func decodesTypingStop() throws {
        let ev = try decode("""
        { "type": "typing.stop",
          "payload": { "conversation_id": 7, "user_id": 3 } }
        """)
        if case .typingStop = ev { return }
        Issue.record("expected .typingStop")
    }

    @Test func decodesPresenceOnline() throws {
        let ev = try decode("""
        { "type": "presence.online", "payload": { "user_id": 3 } }
        """)
        if case .presenceOnline(let p) = ev {
            #expect(p.userId == 3)
        } else {
            Issue.record("expected .presenceOnline")
        }
    }

    @Test func decodesPresenceOffline() throws {
        let ev = try decode("""
        { "type": "presence.offline", "payload": { "user_id": 3 } }
        """)
        if case .presenceOffline = ev { return }
        Issue.record("expected .presenceOffline")
    }

    @Test func decodesFriendRequestNewAcceptedDeclined() throws {
        let fr = """
        { "id": 10, "sender_id": 1, "recipient_id": 2, "status": "pending",
          "created_at": "2026-04-20T09:00:00.000Z",
          "updated_at": "2026-04-20T09:00:00.000Z",
          "username": "alice", "display_name": null, "avatar_url": null }
        """
        let new = try decode(#"{ "type": "friend_request.new", "payload": \#(fr) }"#)
        if case .friendRequestNew = new { } else { Issue.record("expected .friendRequestNew") }

        let accepted = try decode(#"{ "type": "friend_request.accepted", "payload": \#(fr) }"#)
        if case .friendRequestAccepted = accepted { } else { Issue.record("expected .friendRequestAccepted") }

        let declined = try decode(#"{ "type": "friend_request.declined", "payload": \#(fr) }"#)
        if case .friendRequestDeclined = declined { } else { Issue.record("expected .friendRequestDeclined") }
    }

    @Test func unknownTypeDecodesToUnknown() throws {
        let ev = try decode("""
        { "type": "server.experimental", "payload": { "foo": 1 } }
        """)
        if case .unknown(let type) = ev {
            #expect(type == "server.experimental")
        } else {
            Issue.record("expected .unknown")
        }
    }
}
```

- [ ] **Step 5：运行测试确认失败**

```bash
$TEST
```

预期：`WSEvent` 未定义。

- [ ] **Step 6：实现 WSEvent**

`ios-app/EchoIM/Core/Networking/Models/WSEvent.swift`：

```swift
import Foundation

/// 服务端推送的业务事件。`connection.ready` 不放进来——它是 WebSocketClient 内部
/// 握手信号（.handshaking → .ready），不分发给业务订阅者。
/// 遇到未识别 type 时落到 `.unknown(type)`，避免整条 WS 连接因未来协议演进而死
/// （比 decode throw 更宽容）。
enum WSEvent: Decodable, Equatable, Sendable {
    case messageNew(Message)
    case conversationUpdated(ConversationUpdatedPayload)
    case typingStart(ConversationUserPayload)
    case typingStop(ConversationUserPayload)
    case presenceOnline(UserIdPayload)
    case presenceOffline(UserIdPayload)
    case friendRequestNew(FriendRequest)
    case friendRequestAccepted(FriendRequest)
    case friendRequestDeclined(FriendRequest)
    case unknown(String)

    private enum CodingKeys: String, CodingKey { case type, payload }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)

        switch type {
        case "message.new":
            self = .messageNew(try c.decode(Message.self, forKey: .payload))
        case "conversation.updated":
            self = .conversationUpdated(try c.decode(ConversationUpdatedPayload.self, forKey: .payload))
        case "typing.start":
            self = .typingStart(try c.decode(ConversationUserPayload.self, forKey: .payload))
        case "typing.stop":
            self = .typingStop(try c.decode(ConversationUserPayload.self, forKey: .payload))
        case "presence.online":
            self = .presenceOnline(try c.decode(UserIdPayload.self, forKey: .payload))
        case "presence.offline":
            self = .presenceOffline(try c.decode(UserIdPayload.self, forKey: .payload))
        case "friend_request.new":
            self = .friendRequestNew(try c.decode(FriendRequest.self, forKey: .payload))
        case "friend_request.accepted":
            self = .friendRequestAccepted(try c.decode(FriendRequest.self, forKey: .payload))
        case "friend_request.declined":
            self = .friendRequestDeclined(try c.decode(FriendRequest.self, forKey: .payload))
        default:
            self = .unknown(type)
        }
    }
}

struct ConversationUpdatedPayload: Decodable, Equatable, Sendable {
    let conversationId: Int
    let lastReadMessageId: Int
}

struct ConversationUserPayload: Decodable, Equatable, Sendable {
    let conversationId: Int
    let userId: Int
}

struct UserIdPayload: Decodable, Equatable, Sendable {
    let userId: Int
}
```

- [ ] **Step 7：运行测试确认通过**

```bash
$TEST
```

预期：Message 3 个 + WSEvent 9 个共 12 个用例绿；P1/P2 原有测试无回归（搬家 Message 不改行为）。

- [ ] **Step 8：提交**

```bash
git add ios-app/EchoIM/Core/Networking/Models/Message.swift \
        ios-app/EchoIM/Core/Networking/Models/WSEvent.swift \
        ios-app/EchoIM/Core/Networking/APIClient.swift \
        ios-app/EchoIMTests/MessageDecodingTests.swift \
        ios-app/EchoIMTests/WSEventDecodingTests.swift
git commit -m "feat(ios): extract Message model and add WSEvent decoder"
```

---

## Task 2：MessageRepository（list + send text）

**Files:**
- Create: `ios-app/EchoIM/Features/Chat/MessageRepository.swift`
- Modify: `ios-app/EchoIM/Core/Networking/Endpoints.swift`
- Test: `ios-app/EchoIMTests/MessageRepositoryTests.swift`
- Modify: `ios-app/EchoIM/App/AppContainer.swift`（追加 factory）

服务端两个 endpoint：`GET /api/conversations/:id/messages?before=<id>|after=<id>`（服务端不给 `?limit=`，P3 都走默认 50）和 `POST /api/messages`（body `{ recipient_id, body, client_temp_id }`，`message_type` 走 default `'text'`）。

- [ ] **Step 1：扩充 Endpoints**

编辑 `ios-app/EchoIM/Core/Networking/Endpoints.swift`，在 `Conversations` 里追加 messages 构造器，并新增 `Messages`：

```swift
enum Conversations {
    static let list = "api/conversations"

    /// GET /api/conversations/:id/messages?before|after=...
    static func messages(conversationId: Int) -> String {
        "api/conversations/\(conversationId)/messages"
    }

    /// PUT /api/conversations/:id/read
    static func read(conversationId: Int) -> String {
        "api/conversations/\(conversationId)/read"
    }
}

enum Messages {
    static let base = "api/messages"
}
```

- [ ] **Step 2：写 Repository 失败测试**

`ios-app/EchoIMTests/MessageRepositoryTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("MessageRepository")
struct MessageRepositoryTests {
    private let mkBody: (String) -> Data = { $0.data(using: .utf8)! }

    @Test func listInitialHitsEndpointAndDecodes() async throws {
        var capturedURL: URL?
        let body = mkBody("""
        [
          { "id": 10, "conversation_id": 5, "sender_id": 3,
            "body": "older", "message_type": "text", "media_url": null,
            "created_at": "2026-04-20T09:00:00.000Z" },
          { "id": 11, "conversation_id": 5, "sender_id": 9,
            "body": "newer", "message_type": "text", "media_url": null,
            "created_at": "2026-04-20T09:01:00.000Z" }
        ]
        """)
        let (config, _) = MockURLProtocol.configure { req in
            capturedURL = req.url
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let repo = MessageRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        let msgs = try await repo.list(conversationId: 5, cursor: nil, token: "jwt")

        #expect(capturedURL?.path == "/api/conversations/5/messages")
        #expect(capturedURL?.query == nil || capturedURL?.query?.isEmpty == true)
        #expect(msgs.count == 2)
        #expect(msgs[0].id == 10)
    }

    @Test func listBeforeBuildsQuerystring() async throws {
        var capturedURL: URL?
        let (config, _) = MockURLProtocol.configure { req in
            capturedURL = req.url
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, mkBody("[]"))
        }
        let repo = MessageRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        _ = try await repo.list(conversationId: 5, cursor: .before(100), token: "jwt")

        let comps = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)!
        #expect(comps.path == "/api/conversations/5/messages")
        let before = comps.queryItems?.first { $0.name == "before" }?.value
        #expect(before == "100")
    }

    @Test func listAfterBuildsQuerystring() async throws {
        var capturedURL: URL?
        let (config, _) = MockURLProtocol.configure { req in
            capturedURL = req.url
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, mkBody("[]"))
        }
        let repo = MessageRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        _ = try await repo.list(conversationId: 5, cursor: .after(200), token: "jwt")

        let comps = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)!
        let after = comps.queryItems?.first { $0.name == "after" }?.value
        #expect(after == "200")
    }

    @Test func sendTextPostsSnakeCaseBodyAndDecodesResponse() async throws {
        var capturedMethod: String?
        var capturedPath: String?
        var capturedBody: Data?
        let body = mkBody("""
        { "id": 500, "conversation_id": 5, "sender_id": 9,
          "body": "hi", "message_type": "text", "media_url": null,
          "created_at": "2026-04-20T10:00:00.000Z",
          "client_temp_id": "pending-1" }
        """)
        let (config, _) = MockURLProtocol.configure { req in
            capturedMethod = req.httpMethod
            capturedPath = req.url?.path
            if let stream = req.httpBodyStream { capturedBody = Data(reading: stream) }
            else { capturedBody = req.httpBody }
            return (HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, body)
        }
        let repo = MessageRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
        let result = try await repo.sendText(
            recipientId: 3, body: "hi", clientTempId: "pending-1", token: "jwt"
        )

        #expect(capturedMethod == "POST")
        #expect(capturedPath == "/api/messages")
        let dict = try JSONSerialization.jsonObject(with: capturedBody ?? Data()) as? [String: Any]
        #expect(dict?["recipient_id"] as? Int == 3)
        #expect(dict?["body"] as? String == "hi")
        #expect(dict?["client_temp_id"] as? String == "pending-1")
        // 不显式传 message_type，服务端 default 处理
        #expect(dict?["message_type"] == nil)
        #expect(result.id == 500)
        #expect(result.clientTempId == "pending-1")
    }
}
```

（`Data(reading:)` 辅助已在 P2 `FriendRequestRepositoryTests.swift` 定义；Swift Testing 在同 target 里可复用，不要重复声明。）

- [ ] **Step 3：运行测试确认失败**

```bash
$TEST
```

预期：`MessageRepository*` / `MessageCursor` 未定义。

- [ ] **Step 4：实现 Repository**

`ios-app/EchoIM/Features/Chat/MessageRepository.swift`：

```swift
import Foundation

/// 消息分页游标。服务端用全局 SERIAL ID，所以 cursor 是 Int。
enum MessageCursor: Equatable, Sendable {
    case before(Int)   // ?before=<id>：取比该 id 小的，DESC 50 条
    case after(Int)    // ?after=<id>：取比该 id 大的，ASC 50 条
}

protocol MessageRepository {
    /// 无 cursor → 最新 50 条（DESC）
    /// .before → 更早 50 条（DESC）
    /// .after → 更新 50 条（ASC）
    func list(conversationId: Int, cursor: MessageCursor?, token: String) async throws -> [Message]
    func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message
}

private struct SendTextBody: Encodable {
    let recipientId: Int
    let body: String
    let clientTempId: String
    enum CodingKeys: String, CodingKey {
        case recipientId = "recipient_id"
        case body
        case clientTempId = "client_temp_id"
    }
}

@MainActor
final class MessageRepositoryImpl: MessageRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func list(conversationId: Int, cursor: MessageCursor?, token: String) async throws -> [Message] {
        var comps = URLComponents()
        comps.path = Endpoints.Conversations.messages(conversationId: conversationId)
        switch cursor {
        case .before(let id):
            comps.queryItems = [URLQueryItem(name: "before", value: String(id))]
        case .after(let id):
            comps.queryItems = [URLQueryItem(name: "after", value: String(id))]
        case nil:
            break
        }
        let path = comps.path + (comps.percentEncodedQuery.map { "?" + $0 } ?? "")
        return try await api.request(path, token: token)
    }

    func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
        try await api.request(
            Endpoints.Messages.base,
            method: "POST",
            token: token,
            body: SendTextBody(recipientId: recipientId, body: body, clientTempId: clientTempId)
        )
    }
}
```

- [ ] **Step 5：AppContainer 追加 factory**

在 `ios-app/EchoIM/App/AppContainer.swift` 的 `makeConversationRepository()` 后追加：

```swift
func makeMessageRepository() -> MessageRepository {
    MessageRepositoryImpl(api: apiClient)
}
```

- [ ] **Step 6：运行测试确认全绿**

```bash
$TEST
```

预期：4 个 MessageRepository 用例绿；P1/P2 原有全部无回归。

- [ ] **Step 7：编译**

```bash
$BUILD
```

预期：`BUILD SUCCEEDED`。

- [ ] **Step 8：提交**

```bash
git add ios-app/EchoIM/Features/Chat/MessageRepository.swift \
        ios-app/EchoIM/Core/Networking/Endpoints.swift \
        ios-app/EchoIM/App/AppContainer.swift \
        ios-app/EchoIMTests/MessageRepositoryTests.swift
git commit -m "feat(ios): add MessageRepository with cursor-based list and send"
```

---

## Task 3：ReconnectPolicy

**Files:**
- Create: `ios-app/EchoIM/Core/Networking/ReconnectPolicy.swift`
- Test: `ios-app/EchoIMTests/ReconnectPolicyTests.swift`

设计 §7.3：指数退避 + 抖动 + 无限重试（capped 30s）。序列 1s → 2s → 4s → 8s → 16s → 30s → 30s → …；每档叠加 0..(exp * 0.3) 的 jitter。

- [ ] **Step 1：写失败测试**

`ios-app/EchoIMTests/ReconnectPolicyTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@Suite("ReconnectPolicy")
struct ReconnectPolicyTests {
    @Test func firstDelayIsOneSecondPlusJitter() {
        let policy = ReconnectPolicy()
        let d = policy.nextDelay()
        // exp = 1s；jitter 上限 0.3s → 区间 [1.0, 1.3]
        #expect(d >= 1.0)
        #expect(d <= 1.3)
    }

    @Test func exponentialUpToThirtyCap() {
        let policy = ReconnectPolicy()
        // 不考虑 jitter，期望 exp 序列：1, 2, 4, 8, 16, 30, 30, 30, ...
        let expExpected: [Double] = [1, 2, 4, 8, 16, 30, 30, 30, 30, 30]
        for (i, expected) in expExpected.enumerated() {
            let d = policy.nextDelay()
            let upperBound = expected + expected * 0.3 + 0.0001
            #expect(d >= expected)
            #expect(d <= upperBound, "attempt \(i): got \(d), expected ≤ \(upperBound)")
        }
    }

    @Test func resetReturnsToBase() {
        let policy = ReconnectPolicy()
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        policy.reset()
        let d = policy.nextDelay()
        #expect(d <= 1.3)   // 回到 base 档
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`ReconnectPolicy` 未定义。

- [ ] **Step 3：实现 ReconnectPolicy**

`ios-app/EchoIM/Core/Networking/ReconnectPolicy.swift`：

```swift
import Foundation

/// 指数退避 + 抖动 + 无限重试（capped）。线程安全靠外部 @MainActor 持有保证。
/// 设计文档 §7.3。移动网络下"悄悄停止重连"比"持续慢速重试"危险得多（高铁、电梯、长隧道），
/// 故不提供 maxRetries。
final class ReconnectPolicy {
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let jitterRatio: Double
    private var retryCount = 0

    init(baseDelay: TimeInterval = 1.0, maxDelay: TimeInterval = 30.0, jitterRatio: Double = 0.3) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterRatio = jitterRatio
    }

    func nextDelay() -> TimeInterval {
        let exp = min(baseDelay * pow(2.0, Double(retryCount)), maxDelay)
        let jitter = Double.random(in: 0...(exp * jitterRatio))
        retryCount += 1
        return exp + jitter
    }

    func reset() {
        retryCount = 0
    }
}
```

- [ ] **Step 4：运行测试确认通过**

```bash
$TEST
```

预期：3 个用例绿。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Core/Networking/ReconnectPolicy.swift \
        ios-app/EchoIMTests/ReconnectPolicyTests.swift
git commit -m "feat(ios): add ReconnectPolicy with exponential backoff and jitter"
```

---

## Task 4：WebSocketClient 基础（连接 + 握手 + 事件分发）

**Files:**
- Create: `ios-app/EchoIM/Core/Networking/WebSocketClient.swift`
- Modify: `ios-app/EchoIM/Core/Networking/Endpoints.swift`

**动机：** 整块 WS 生命周期是本阶段技术核心，拆三步（Task 4/5/6）：**Task 4** 搭架子——`URLSessionWebSocketTask` + delegate + 状态机（disconnected/connecting/handshaking/ready/reconnecting）+ `connection.ready` 内部消化 + 事件分发；**Task 5** 加心跳 + NWPathMonitor；**Task 6** 做 401 识别 + AppContainer 集成 + scenePhase。

`WebSocketClient` 的测试策略（见文件顶部的 TDD 范围说明）：不做纯单元测试（`URLSessionWebSocketTask` 难以 mock；引 protocol abstraction 成本 > 收益）。正确性靠**模拟器手工验证**（Task 6 / Task 12 清单）+ XCUITest smoke。单元层面我们只测 `WSEvent` 解码（Task 1）、`ReconnectPolicy`（Task 3）、`ChatViewModel` 的状态机（Task 8-11）。

- [ ] **Step 1：Endpoints 追加 WS URL helper**

编辑 `ios-app/EchoIM/Core/Networking/Endpoints.swift`，追加：

```swift
/// 把 baseURL 的 http/https scheme 换成 ws/wss，拼出带 token 的 /ws url。
static func webSocketURL(token: String) -> URL? {
    guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
        return nil
    }
    // baseURL 的 path 通常是 "/"；WS 走固定 /ws
    comps.path = "/ws"
    switch comps.scheme?.lowercased() {
    case "https": comps.scheme = "wss"
    case "http":  comps.scheme = "ws"
    default:      return nil
    }
    comps.queryItems = [URLQueryItem(name: "token", value: token)]
    return comps.url
}
```

- [ ] **Step 2：实现 WebSocketClient（基础骨架）**

`ios-app/EchoIM/Core/Networking/WebSocketClient.swift`：

```swift
import Foundation
import Observation

/// WS 生命周期状态机。设计文档 §7.4。
/// .handshaking → .ready 的切换由服务端 "connection.ready" 文本帧触发；
/// 此帧 **不** 分发给业务订阅者。
enum WSState: Equatable, Sendable {
    case disconnected
    case connecting
    case handshaking
    case ready
    case reconnecting(in: TimeInterval)
}

enum WSDisconnectReason: Equatable, Sendable {
    case userInitiated      // logout / app backgrounded
    case unauthorized       // HTTP 401 on upgrade
    case transport          // TCP / pong timeout / unknown failure
    case networkLost        // NWPathMonitor unsatisfied
}

/// 订阅令牌。ViewModel 在 onDisappear / deinit 前调 `cancel()`。
final class WSSubscription {
    fileprivate let id: UUID
    fileprivate weak var client: WebSocketClient?
    fileprivate init(id: UUID, client: WebSocketClient) {
        self.id = id
        self.client = client
    }
    @MainActor
    func cancel() {
        client?.unsubscribe(self.id)
    }
}

@MainActor
@Observable
final class WebSocketClient: NSObject {
    // MARK: - Public observable state
    private(set) var state: WSState = .disconnected

    // MARK: - Dependencies
    private let tokenProvider: @MainActor () -> String?
    /// 401 时触发；由 AppContainer 注入 `handleUnauthorized`（Task 6）。
    private let onUnauthorized: @MainActor () -> Void
    private let reconnectPolicy: ReconnectPolicy

    // MARK: - URLSession / task
    private var urlSession: URLSession?
    private var task: URLSessionWebSocketTask?

    // MARK: - Subscribers
    private var handlers: [UUID: (WSEvent) -> Void] = [:]
    private var readyHandlers: [UUID: @MainActor () -> Void] = [:]

    // MARK: - Reconnect
    private var reconnectTimer: Task<Void, Never>?
    private var shouldReconnect = false

    init(
        tokenProvider: @escaping @MainActor () -> String?,
        onUnauthorized: @escaping @MainActor () -> Void,
        reconnectPolicy: ReconnectPolicy = ReconnectPolicy()
    ) {
        self.tokenProvider = tokenProvider
        self.onUnauthorized = onUnauthorized
        self.reconnectPolicy = reconnectPolicy
        super.init()
    }

    // MARK: - Public lifecycle

    /// 空闲或重连定时器等待中都能调——如果已连上直接 no-op。
    func connectIfNeeded() {
        shouldReconnect = true
        switch state {
        case .connecting, .handshaking, .ready:
            return
        case .disconnected, .reconnecting:
            reconnectTimer?.cancel()
            reconnectTimer = nil
            reconnectPolicy.reset()
            openSocket()
        }
    }

    /// 外部主动断开（登出 / 进后台）；不触发重连。
    func disconnect(reason: WSDisconnectReason) {
        shouldReconnect = false
        reconnectTimer?.cancel()
        reconnectTimer = nil
        closeTaskLocally()
        state = .disconnected
    }

    // MARK: - Subscription

    func subscribe(_ handler: @escaping (WSEvent) -> Void) -> WSSubscription {
        let id = UUID()
        handlers[id] = handler
        return WSSubscription(id: id, client: self)
    }

    func onReady(_ handler: @escaping @MainActor () -> Void) -> WSSubscription {
        let id = UUID()
        readyHandlers[id] = handler
        return WSSubscription(id: id, client: self)
    }

    fileprivate func unsubscribe(_ id: UUID) {
        handlers.removeValue(forKey: id)
        readyHandlers.removeValue(forKey: id)
    }

    // MARK: - Internal

    private func openSocket() {
        guard let token = tokenProvider() else {
            // 没 token 直接进 disconnected；调用方（AppContainer）负责在登录后重新 connect
            state = .disconnected
            return
        }
        guard let url = Endpoints.webSocketURL(token: token) else {
            state = .disconnected
            return
        }

        // URLSession delegate 绑定自己——能在 401 / didComplete 里分辨 statusCode
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.urlSession = session

        state = .connecting

        let newTask = session.webSocketTask(with: url)
        self.task = newTask
        newTask.resume()
        startReceiveLoop()
    }

    private func closeTaskLocally() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        switch state {
        case .ready, .connecting, .handshaking:
            break
        case .disconnected, .reconnecting:
            return
        }
        closeTaskLocally()
        let delay = reconnectPolicy.nextDelay()
        state = .reconnecting(in: delay)
        reconnectTimer?.cancel()
        reconnectTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.openSocket()
        }
    }

    // MARK: - Receive loop

    private func startReceiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handleReceivedMessage(message)
                    // 继续循环；receive() 只消费一帧
                    self.startReceiveLoop()
                case .failure:
                    // 交给 delegate.didCompleteWithError 统一处理（401 vs 网络）
                    // 这里不直接 scheduleReconnect，避免双路径
                    break
                }
            }
        }
    }

    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d):   text = String(data: d, encoding: .utf8) ?? ""
        @unknown default:    return
        }
        guard let data = text.data(using: .utf8) else { return }

        // 先检查是不是 connection.ready 握手信号——不进业务 decode
        if let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           frame["type"] as? String == "connection.ready" {
            if case .handshaking = state {
                state = .ready
                reconnectPolicy.reset()
                for h in Array(readyHandlers.values) { h() }
            }
            return
        }

        do {
            let event = try APIClient.jsonDecoder.decode(WSEvent.self, from: data)
            // .unknown 也 dispatch——业务侧可选择忽略，比全屏抛更好调试
            for h in handlers.values { h(event) }
        } catch {
            // decode 失败不拖垮连接：只吞掉一帧
            // TODO(P8): 接日志框架时记 warning
        }
    }
}

extension WebSocketClient: URLSessionWebSocketDelegate, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        // TCP + WS upgrade 成功，等服务端 connection.ready
        Task { @MainActor in
            if case .connecting = self.state {
                self.state = .handshaking
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            self.scheduleReconnect()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // Task 6 会在这里加 401 分支；本 Task 只走通用重连
        Task { @MainActor in
            switch self.state {
            case .disconnected, .reconnecting:
                return                     // 我们主动关的，不再触发重连
            default:
                self.scheduleReconnect()
            }
        }
    }
}
```

**关键点说明**：
- `WSState` / `WSDisconnectReason` / `WSSubscription` 分别是 Sendable value / Sendable enum / token。handlers 用字典 + UUID key，避免 NSHashTable 的 ObjC 开销。
- `connection.ready` 在 `handleReceivedMessage` 早返回吞掉，不进 `WSEvent.decode`；同时触发 `onReady` 回调，供会话列表刷新和聊天页补拉使用。
- delegate 方法标 `nonisolated`，里面用 `Task { @MainActor in ... }` 跳回 main actor（URLSession delegate 回调不在 main 上）。
- 网络层错误全部走 `didCompleteWithError`——`didCloseWith` 是 WS 协议层（服务端主动 close），两处都最终 `scheduleReconnect()`。Task 5/6 会增强这里的分支判断。

- [ ] **Step 3：编译**

```bash
$BUILD
```

预期：`BUILD SUCCEEDED`。此时 WebSocketClient 存在但没人构造它（AppContainer 在 Task 6 接入）。

- [ ] **Step 4：提交**

```bash
git add ios-app/EchoIM/Core/Networking/WebSocketClient.swift \
        ios-app/EchoIM/Core/Networking/Endpoints.swift
git commit -m "feat(ios): add WebSocketClient skeleton with handshake and reconnection"
```

---


## Task 5：WebSocketClient 心跳 + 网络监控

**Files:**
- Modify: `ios-app/EchoIM/Core/Networking/WebSocketClient.swift`

**动机：** 设计 §7.6 要求 30s ping + 10s pong 超时；§7.2 要求 `NWPathMonitor` 感知网络恢复、立即抢一次重连。这两块与 Task 4 的基础连接**并存**（都是死连接的兜底 + 恢复抢跑），单独一步加进去便于独立验证。

- [ ] **Step 1：加心跳字段 + 计时器**

编辑 `ios-app/EchoIM/Core/Networking/WebSocketClient.swift`，在 `reconnectTimer` 下方追加：

```swift
// MARK: - Heartbeat
private var heartbeatTask: Task<Void, Never>?
private var pendingPongContinuation: CheckedContinuation<Void, Error>?
private let heartbeatInterval: TimeInterval = 30.0
private let pongTimeout: TimeInterval = 10.0
```

- [ ] **Step 2：实现 startHeartbeat / stopHeartbeat**

在 `closeTaskLocally` 之后追加：

```swift
private func startHeartbeat() {
    stopHeartbeat()
    heartbeatTask = Task { [weak self] in
        while !Task.isCancelled {
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.heartbeatInterval * 1_000_000_000))
            if Task.isCancelled { return }
            await self.sendPingWithTimeout()
        }
    }
}

private func stopHeartbeat() {
    heartbeatTask?.cancel()
    heartbeatTask = nil
}

private func sendPingWithTimeout() async {
    guard let task, case .ready = state, pendingPongContinuation == nil else { return }

    do {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.pendingPongContinuation = cont

            let timeoutItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self, let c = self.pendingPongContinuation else { return }
                    self.pendingPongContinuation = nil
                    c.resume(throwing: URLError(.timedOut))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + self.pongTimeout, execute: timeoutItem)

            task.sendPing { [weak self] error in
                Task { @MainActor in
                    guard let self, let c = self.pendingPongContinuation else { return }
                    timeoutItem.cancel()
                    self.pendingPongContinuation = nil
                    if let error {
                        c.resume(throwing: error)
                    } else {
                        c.resume()
                    }
                }
            }
        }
    } catch {
        scheduleReconnect()
    }
}
```

这里用 `pendingPongContinuation` 防止 timeout 和 `sendPing` completion 双 resume；不要用没有保护的 `CheckedContinuation` 版本。

- [ ] **Step 3：在 handshake 完成时 startHeartbeat，断开时 stopHeartbeat**

编辑 `handleReceivedMessage` 里 `connection.ready` 分支：

```swift
if let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
   frame["type"] as? String == "connection.ready" {
    if case .handshaking = state {
        state = .ready
        reconnectPolicy.reset()
        startHeartbeat()        // 新增
        for h in Array(readyHandlers.values) { h() }
    }
    return
}
```

编辑 `closeTaskLocally`：

```swift
private func closeTaskLocally() {
    stopHeartbeat()             // 新增
    if let c = pendingPongContinuation {
        pendingPongContinuation = nil
        c.resume(throwing: CancellationError())
    }
    task?.cancel(with: .normalClosure, reason: nil)
    task = nil
    urlSession?.invalidateAndCancel()
    urlSession = nil
}
```

- [ ] **Step 4：NWPathMonitor 接入**

在文件顶部 `import Observation` 下加 `import Network`。

在 `WebSocketClient` 里追加：

```swift
// MARK: - Network monitor
private let pathMonitor = NWPathMonitor()
private var networkMonitorStarted = false

private func startNetworkMonitorIfNeeded() {
    guard !networkMonitorStarted else { return }
    networkMonitorStarted = true

    pathMonitor.pathUpdateHandler = { [weak self] path in
        Task { @MainActor in
            guard let self else { return }
            if path.status == .satisfied {
                // 网络恢复——如果处于重连态，立刻抢一次重连。
                // 注意：.disconnected 可能是后台/登出主动断开，不能被网络恢复偷偷拉起。
                switch self.state {
                case .reconnecting where self.shouldReconnect:
                    self.reconnectTimer?.cancel()
                    self.reconnectTimer = nil
                    self.reconnectPolicy.reset()
                    self.openSocket()
                default:
                    break
                }
            }
            // 网络断开我们不主动 close——delegate.didCompleteWithError 会在请求失败时触发 reconnect
            // 主动 close 会与系统重试赛跑，反而制造更多噪声
        }
    }
    pathMonitor.start(queue: DispatchQueue(label: "WebSocketClient.path"))
}
```

在 `init` 末尾调用 `startNetworkMonitorIfNeeded()`（只启动一次，WebSocketClient 生命周期与 AppContainer/UserSession 对齐，不需要 `stop()`）。

- [ ] **Step 5：编译**

```bash
$BUILD
```

预期：`BUILD SUCCEEDED`。

- [ ] **Step 6：提交**

```bash
git add ios-app/EchoIM/Core/Networking/WebSocketClient.swift
git commit -m "feat(ios): add WS heartbeat and NWPathMonitor-driven reconnect"
```

---

## Task 6：WebSocketClient 401 识别 + AppContainer 集成

**Files:**
- Modify: `ios-app/EchoIM/Core/Networking/WebSocketClient.swift`
- Modify: `ios-app/EchoIM/App/AppContainer.swift`

**动机：** 设计 §10 明确：`URLSessionWebSocketTask` 闭包式 init 拿不到 HTTP 升级响应，必须用 delegate 的 `didCompleteWithError` 读 `task.response as? HTTPURLResponse` 的 statusCode。401 → 踢登录态；其他错误 → 走 Task 4/5 的重连路径。同时把 WebSocketClient 的生命周期挂到 `AppContainer.handleLoginSuccess` / `logout` / 新的 `handleUnauthorized` 上——这三个钩子决定"WS 什么时候连 / 什么时候断"。

- [ ] **Step 1：WebSocketClient didComplete 加 401 分支**

编辑 `urlSession(_:task:didCompleteWithError:)`：

```swift
nonisolated func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
) {
    let httpStatus = (task.response as? HTTPURLResponse)?.statusCode
    Task { @MainActor in
        if httpStatus == 401 {
            // 设计 §10：WS upgrade 401 是一个完整 HTTP 响应，能在 didCompleteWithError 拿到
            self.shouldReconnect = false
            self.stopHeartbeat()
            self.reconnectTimer?.cancel()
            self.reconnectTimer = nil
            self.closeTaskLocally()
            self.state = .disconnected
            self.onUnauthorized()
            return
        }

        switch self.state {
        case .disconnected, .reconnecting:
            return
        default:
            self.scheduleReconnect()
        }
    }
}
```

- [ ] **Step 2：AppContainer 持有 WebSocketClient + 集成三个钩子**

编辑 `ios-app/EchoIM/App/AppContainer.swift`，全量替换为：

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AppContainer {
    let tokenStore: KeychainTokenStore
    let apiClient: APIClient
    var currentUser: AuthenticatedUser?

    /// 仅 `-uitest-reset-keychain` 等 UI 测试参数会把它设为 true；每次启动都从未登录态开始。
    private let resetKeychainOnLaunch: Bool

    /// 懒构造：只有登录后（有 token）才创建；登出时释放（见 tearDownSession）。
    /// 这样无登录态时完全不占用 URLSession / NWPathMonitor 资源。
    private(set) var wsClient: WebSocketClient?

    init(
        tokenStore: KeychainTokenStore? = nil,
        apiClient: APIClient? = nil,
        resetKeychainOnLaunch: Bool = false
    ) {
        self.tokenStore = tokenStore ?? KeychainTokenStore()
        self.apiClient = apiClient ?? APIClient()
        self.resetKeychainOnLaunch = resetKeychainOnLaunch
    }

    // MARK: - Repositories（P2/P3 既有）

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

    func makeMessageRepository() -> MessageRepository {
        MessageRepositoryImpl(api: apiClient)
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
        ensureWSClient()
    }

    func handleLoginSuccess(_ response: AuthResponse) {
        currentUser = response.user
        ensureWSClient()
    }

    func refreshCurrentUser() async {
        guard let stored = try? tokenStore.load() else { return }
        do {
            let user = try await makeUserRepository().fetchMe(token: stored.token)
            currentUser = user
        } catch APIError.unauthorized {
            try? tokenStore.clear()
            await tearDownSession()
        } catch {
            // 保留占位态
        }
    }

    func logout() async {
        await makeAuthRepository().logout()
        await tearDownSession()
    }

    /// WS 收到 upgrade 401 时回调。与 logout 行为几乎等价——清 token + 释放资源 + 回登录页。
    /// 不同点是不调 /api/auth/logout（反正 token 已失效，打也没意义）。
    func handleUnauthorized() async {
        try? tokenStore.clear()
        await tearDownSession()
    }

    /// 设计 §2.2 的 tearDownSession（P3 精简版）：本阶段只断 WS + 清 currentUser；
    /// Nuke 与 SwiftData 的清理 P4/P5 接入各自机制时再补——那时会把这里扩成 §5.5 的完整三阶段。
    func tearDownSession() async {
        wsClient?.disconnect(reason: .userInitiated)
        wsClient = nil
        currentUser = nil
    }

    // MARK: - Internal

    private func ensureWSClient() {
        guard wsClient == nil, (try? tokenStore.load()) != nil else { return }
        let client = WebSocketClient(
            tokenProvider: { [tokenStore = self.tokenStore] in
                (try? tokenStore.load())?.token
            },
            onUnauthorized: { [weak self] in
                Task { @MainActor in
                    await self?.handleUnauthorized()
                }
            }
        )
        wsClient = client
        client.connectIfNeeded()
    }
}
```

**关键点**：
- `ensureWSClient()` 是唯一的 WS 生命周期入口——bootstrap（有 token）/ handleLoginSuccess 都调。已经有 client 时 no-op（连接状态由 WebSocketClient 自己管）。
- `tearDownSession()` 是 logout / 401 的公共出口。P3 先实现精简版，P4/P5 会扩展（设计 §5.5）。
- `onUnauthorized` 闭包用 weak self + Task + `handleUnauthorized()` 组合——闭包是 nonisolated-caller safe 的（内部 Task `@MainActor`）。

- [ ] **Step 3：编译**

```bash
$BUILD
```

预期：`BUILD SUCCEEDED`。P1/P2 AppContainerRefreshTests / AppContainerTests 里对 `logout()` 的行为断言可能需要更新——原先 `logout()` 只做 `makeAuthRepository().logout() + currentUser = nil`，现在增加了 `tearDownSession`（断 WS + wsClient = nil）。检查测试：

```bash
$TEST
```

如果 `AppContainerRefreshTests` 的 `refreshClearsKeychainOn401` 用例挂掉，确认行为——期望依然是 `currentUser == nil` + keychain 清空。401 分支要先清 token，再走 `tearDownSession()` 释放 WS 和登录态。

- [ ] **Step 4：提交**

```bash
git add ios-app/EchoIM/Core/Networking/WebSocketClient.swift \
        ios-app/EchoIM/App/AppContainer.swift
git commit -m "feat(ios): handle WS 401 and wire lifecycle into AppContainer"
```

---

## Task 7：scenePhase 联动 + RootView 装配

**Files:**
- Modify: `ios-app/EchoIM/App/RootView.swift`

**动机：** 设计 §7.1：App `.active` → 保 WS；`.background` → 主动断（iOS 会挂起进程，没 APNs 也收不到，断开再重连反而比"带着死连接"稳定）。`@Environment(\.scenePhase)` 只能在 View 里观察，所以这段逻辑必须落到 RootView（或 MainTabView），由 AppContainer 的 `wsClient` 执行断连。

- [ ] **Step 1：RootView 加 scenePhase 联动**

编辑 `ios-app/EchoIM/App/RootView.swift`，全量替换：

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
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, newPhase in
            guard container.currentUser != nil else { return }
            switch newPhase {
            case .active:
                container.wsClient?.connectIfNeeded()
            case .background:
                container.wsClient?.disconnect(reason: .userInitiated)
            case .inactive:
                // 通知中心 / 锁屏瞬间等过渡态 → 保持连接
                break
            @unknown default:
                break
            }
        }
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

- [ ] **Step 2：编译 + 测试**

```bash
$BUILD
$TEST
```

预期：全绿。

- [ ] **Step 3：模拟器手工验证（WS 连接生命周期）**

后端在跑；Xcode 日志窗口能看到 WebSocketClient 对 `/ws` 的请求（看 URLSession 日志或 print）。建议临时在 `WebSocketClient.openSocket()` 加一行 `print("[WS] openSocket -> \(url)")` 方便观察，验证完移除（或放到 `#if DEBUG` 包起来作为日常工具）。

- [ ] 登录 A 账号 → 进 MainTabView → 观察日志：应有一次 openSocket → didOpen → connection.ready 文本帧
- [ ] App 切后台（按 Home / 滑上）→ scenePhase 进 background → WS 主动断开（observe state → .disconnected）
- [ ] App 切回前台 → scenePhase 进 active → openSocket 再连一次 → 重新 ready
- [ ] 点"登出" → tearDownSession → WS 断开 + wsClient = nil + 回 LoginView
- [ ] 断开 Mac Wi-Fi（或模拟器 "Device → Wi-Fi → Disable"）→ 观察 WS 断开 / 进入 reconnecting 退避
- [ ] 恢复 Wi-Fi → NWPathMonitor 回调 → 立刻抢跑重连 → ready

- [ ] **Step 4：提交**

```bash
git add ios-app/EchoIM/App/RootView.swift
git commit -m "feat(ios): drive WS connect/disconnect from scenePhase"
```

---


## Task 8：LocalMessage / MessageSendState + ChatViewModel 骨架（加载 + 分页）

**Files:**
- Create: `ios-app/EchoIM/Features/Chat/LocalMessage.swift`
- Create: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`
- Create: `ios-app/EchoIM/Features/Chat/ChatRoute.swift`
- Modify: `ios-app/EchoIM/Core/Networking/Models/Conversation.swift`
- Test: `ios-app/EchoIMTests/ChatViewModelLoadTests.swift`

**动机：** 先把"单个会话的消息状态 + 加载 + 上滑分页"做出来，打底。发送、WS、markRead 放到 Task 9-11 逐步追加。`LocalMessage` 是 Sendable struct（`Message` + 发送态 + P5 预留的 `localImageData`——P3 保留字段但不用）。

**草稿对话（`conversationId == nil`）场景**：Contacts tap 一个从未聊过的好友时，`ChatViewModel` 初始化只带 peer，不带 conversationId。本 Task 的 load/分页逻辑在草稿态下要短路：`await load()` 跳过网络调用（没有 conversation 可拉），`loadOlder()` 同理。

- [ ] **Step 1：Conversation Hashable + ChatRoute 与 LocalMessage**

`ChatRoute` 要作为 `NavigationStack.navigationDestination(for:)` 的 value，必须 `Hashable`。`UserProfile` 已经是 `Hashable`，所以先把 `Conversation` 同步补上：

```swift
struct Conversation: Identifiable, Equatable, Sendable, Hashable {
    // 字段不变
}
```

`ios-app/EchoIM/Features/Chat/ChatRoute.swift`：

```swift
import Foundation

/// 从会话列表 / 联系人进入 ChatView 的两种来源。Hashable 用于 NavigationStack.navigationDestination。
enum ChatRoute: Hashable {
    case conversation(Conversation)
    case peer(UserProfile)
}
```

`ios-app/EchoIM/Features/Chat/LocalMessage.swift`：

```swift
import Foundation

enum MessageSendState: Equatable, Sendable {
    case confirmed         // 服务端已存在（列表拉回来的、WS 推来的）
    case pending           // 乐观发送中
    case failed(String)    // 失败，附一行错误描述
}

/// ChatViewModel 持有的消息状态。一条消息的身份有两个可能 key：
/// - 已确认消息：`message.id`（Int）
/// - 草稿/pending：`localId`（客户端生成的 UUID 字符串，对应 `clientTempId`）
///
/// 服务端 201 回来后用 clientTempId 把 pending 合并为 confirmed。
/// `localImageData` P3 不用（预留给 P5）。
struct LocalMessage: Identifiable, Equatable, Sendable {
    let localId: String        // `clientTempId` for pending / "id-\(message.id)" for confirmed
    var message: Message
    var sendState: MessageSendState
    var localImageData: Data?

    var id: String { localId }

    static func confirmed(_ message: Message) -> LocalMessage {
        LocalMessage(
            localId: "id-\(message.id)",
            message: message,
            sendState: .confirmed,
            localImageData: nil
        )
    }
}
```

- [ ] **Step 2：写 ChatViewModel 加载失败测试**

`ios-app/EchoIMTests/ChatViewModelLoadTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ChatViewModel — load / paginate")
struct ChatViewModelLoadTests {
    final class FakeMessageRepo: MessageRepository {
        var listResult: Result<[Message], Error> = .success([])
        private(set) var calls: [(Int, MessageCursor?)] = []
        func list(conversationId: Int, cursor: MessageCursor?, token: String) async throws -> [Message] {
            calls.append((conversationId, cursor))
            return try listResult.get()
        }
        func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
            throw APIError.invalidResponse
        }
    }

    /// WebSocketClient 的 mock：ChatViewModel 只用 subscribe() —— 真实实例不会启动连接。
    /// 但本 suite 暂时不用 WS，给一个最小的 stub 接口。
    final class FakeWSClient {
        // ChatViewModel 在后续 Task 接入 subscribe；本 Task 先用可空 WebSocketClient 注入
    }

    private func makeMessage(id: Int, body: String) -> Message {
        Message(
            id: id, conversationId: 5, senderId: 3,
            body: body, messageType: "text", mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
            clientTempId: nil
        )
    }

    @Test
    func loadLatestReversesDescToAscendingChronological() async {
        let repo = FakeMessageRepo()
        // 服务端返回 DESC（最新在前）
        repo.listResult = .success([
            makeMessage(id: 3, body: "c"),
            makeMessage(id: 2, body: "b"),
            makeMessage(id: 1, body: "a"),
        ])
        let vm = ChatViewModel(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )
        await vm.load()

        #expect(vm.messages.count == 3)
        #expect(vm.messages[0].message.id == 1)   // 最旧在最前（聊天窗的时间序）
        #expect(vm.messages[2].message.id == 3)
        #expect(vm.phase == .loaded)
    }

    @Test
    func loadEmptyShowsEmptyPhase() async {
        let repo = FakeMessageRepo()
        repo.listResult = .success([])
        let vm = ChatViewModel(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )
        await vm.load()
        #expect(vm.messages.isEmpty)
        #expect(vm.phase == .loaded)
    }

    @Test
    func loadErrorSetsErrorPhase() async {
        let repo = FakeMessageRepo()
        repo.listResult = .failure(APIError.invalidResponse)
        let vm = ChatViewModel(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )
        await vm.load()
        if case .error = vm.phase { return }
        Issue.record("expected .error")
    }

    @Test
    func loadOlderAppendsToTopWithBeforeCursor() async {
        let repo = FakeMessageRepo()
        // 初次
        repo.listResult = .success([
            makeMessage(id: 30, body: "c"),
            makeMessage(id: 29, body: "b"),
            makeMessage(id: 28, body: "a"),
        ])
        let vm = ChatViewModel(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )
        await vm.load()
        #expect(vm.messages.first?.message.id == 28)

        // 上滑加载更老
        repo.listResult = .success([
            makeMessage(id: 27, body: "older2"),
            makeMessage(id: 26, body: "older1"),
        ])
        await vm.loadOlder()

        #expect(vm.messages.count == 5)
        #expect(vm.messages[0].message.id == 26)
        #expect(vm.messages[1].message.id == 27)
        #expect(vm.messages[2].message.id == 28)
        // cursor 是 loadOlder 时的 oldest (28)
        #expect(repo.calls[1].1 == .before(28))
    }

    @Test
    func draftRouteSkipsNetwork() async {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .peer(UserProfile(id: 9, username: "alice", displayName: nil, avatarUrl: nil)),
            currentUserId: 3,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )
        await vm.load()
        #expect(repo.calls.isEmpty)
        #expect(vm.messages.isEmpty)
        #expect(vm.phase == .loaded)
    }

    private func makeConversation(id: Int, peerId: Int) -> Conversation {
        // 用服务端同形 JSON 造 fixture，顺便覆盖 peer_* → UserProfile 的解码路径。
        let json = """
        {
          "id": \(id),
          "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": \(peerId), "peer_username": "alice",
          "peer_display_name": null, "peer_avatar_url": null,
          "last_message_body": null, "last_message_type": null,
          "last_message_sender_id": null, "last_message_at": null,
          "last_read_message_id": null, "unread_count": 0
        }
        """.data(using: .utf8)!
        return try! APIClient.jsonDecoder.decode(Conversation.self, from: json)
    }
}
```

- [ ] **Step 3：运行测试确认失败**

```bash
$TEST
```

预期：`ChatViewModel` 未定义。

- [ ] **Step 4：实现 ChatViewModel 骨架**

`ios-app/EchoIM/Features/Chat/ChatViewModel.swift`：

```swift
import Foundation
import Observation

enum ChatPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@Observable
@MainActor
final class ChatViewModel {
    // MARK: - State
    private(set) var messages: [LocalMessage] = []
    private(set) var phase: ChatPhase = .idle
    private(set) var isLoadingOlder = false
    private(set) var hasMoreOlder = true

    // MARK: - Identity
    /// 当前会话 id；草稿态（从 Contacts 点进来、两人未聊过）初始为 nil，
    /// 收到首条消息 201 回包或 WS message.new 后回填。
    private(set) var conversationId: Int?
    let peer: UserProfile
    private let currentUserId: Int

    // MARK: - Dependencies
    private let messageRepo: MessageRepository
    private let conversationRepository: ConversationRepository?
    weak var wsClient: WebSocketClient?
    private let tokenProvider: @MainActor () -> String?

    // MARK: - Tempid seq
    private var tempSeq = 0

    init(
        route: ChatRoute,
        currentUserId: Int,
        messageRepo: MessageRepository,
        wsClient: WebSocketClient?,
        conversationRepository: ConversationRepository? = nil,
        tokenProvider: @escaping @MainActor () -> String?
    ) {
        switch route {
        case .conversation(let conv):
            self.conversationId = conv.id
            self.peer = conv.peer
        case .peer(let p):
            self.conversationId = nil
            self.peer = p
        }
        self.currentUserId = currentUserId
        self.messageRepo = messageRepo
        self.conversationRepository = conversationRepository
        self.wsClient = wsClient
        self.tokenProvider = tokenProvider
    }

    // MARK: - Load

    func load() async {
        // 草稿态 → 没 conversation 可拉
        guard let convId = conversationId else {
            phase = .loaded
            hasMoreOlder = false
            return
        }
        guard let token = tokenProvider() else {
            phase = .error("unauthenticated")
            return
        }

        phase = .loading
        do {
            let rows = try await messageRepo.list(conversationId: convId, cursor: nil, token: token)
            // 服务端 DESC；反转成聊天时间序
            messages = rows.reversed().map(LocalMessage.confirmed)
            hasMoreOlder = rows.count == 50
            phase = .loaded
        } catch {
            phase = .error(String(describing: error))
        }
    }

    func loadOlder() async {
        guard let convId = conversationId, !isLoadingOlder, hasMoreOlder else { return }
        guard let oldest = messages.first?.message.id else { return }
        guard let token = tokenProvider() else { return }

        isLoadingOlder = true
        defer { isLoadingOlder = false }

        do {
            let rows = try await messageRepo.list(
                conversationId: convId, cursor: .before(oldest), token: token
            )
            // rows 是 DESC；反转后插到顶端
            let older = rows.reversed().map(LocalMessage.confirmed)
            messages.insert(contentsOf: older, at: 0)
            hasMoreOlder = rows.count == 50
        } catch {
            // 静默失败——下一次上滑可重试；不覆盖 phase
        }
    }

    // MARK: - Tempid helper（Task 9/10 会用）

    fileprivate func makeTempId() -> String {
        tempSeq += 1
        return "pending-\(Int(Date().timeIntervalSince1970))-\(tempSeq)"
    }
}
```

- [ ] **Step 5：运行测试确认通过**

```bash
$TEST
```

预期：5 个 load 用例绿。

- [ ] **Step 6：提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
        ios-app/EchoIM/Features/Chat/LocalMessage.swift \
        ios-app/EchoIM/Features/Chat/ChatRoute.swift \
        ios-app/EchoIM/Core/Networking/Models/Conversation.swift \
        ios-app/EchoIMTests/ChatViewModelLoadTests.swift
git commit -m "feat(ios): add ChatViewModel load/paginate and LocalMessage type"
```

---

## Task 9：ChatViewModel 乐观发送 + 合并 + 失败重试

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`
- Test: `ios-app/EchoIMTests/ChatViewModelSendTests.swift`

**动机：** 乐观发送的状态机是 P3 最容易出 bug 的地方——涉及"REST 回包 vs WS echo 谁先到"、"草稿态首条消息回填 conversationId"、"失败 → failed UI → 重试"三条交叉路径。单独一步覆盖。

**已知妥协**：重试可能造成服务端重复行——见文件顶部"已知妥协"。

- [ ] **Step 1：写发送测试**

`ios-app/EchoIMTests/ChatViewModelSendTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ChatViewModel — send / retry")
struct ChatViewModelSendTests {
    final class FakeMessageRepo: MessageRepository {
        var listResult: Result<[Message], Error> = .success([])
        var sendResult: Result<Message, Error> = .failure(APIError.invalidResponse)
        var sendDelay: TimeInterval = 0
        private(set) var sendCalls: [(recipientId: Int, body: String, tempId: String)] = []
        func list(conversationId: Int, cursor: MessageCursor?, token: String) async throws -> [Message] {
            try listResult.get()
        }
        func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
            sendCalls.append((recipientId, body, clientTempId))
            if sendDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(sendDelay * 1_000_000_000))
            }
            return try sendResult.get()
        }
    }

    private let peer = UserProfile(id: 9, username: "alice", displayName: nil, avatarUrl: nil)

    private func makeVM(
        route: ChatRoute,
        currentUserId: Int,
        repo: FakeMessageRepo
    ) -> ChatViewModel {
        ChatViewModel(
            route: route,
            currentUserId: currentUserId,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "jwt" }
        )
    }

    private func srvMessage(
        id: Int, convId: Int = 5, senderId: Int = 3,
        body: String = "hi", tempId: String? = nil
    ) -> Message {
        Message(
            id: id, conversationId: convId, senderId: senderId,
            body: body, messageType: "text", mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
            clientTempId: tempId
        )
    }

    @Test
    func sendOptimisticallyAppendsPendingBubble() async {
        let repo = FakeMessageRepo()
        // 让 send 阻塞 50ms，能断言 pending 态先到
        repo.sendDelay = 0.05
        repo.sendResult = .success(srvMessage(id: 500, senderId: 3, body: "hi", tempId: "pending-X"))
        let vm = makeVM(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 3, repo: repo
        )

        let task = Task { await vm.sendText("hi") }

        // 等 VM 把 optimistic bubble 入队
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].sendState == .pending)
        #expect(vm.messages[0].message.body == "hi")

        await task.value

        // 回包后合并为 confirmed
        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].sendState == .confirmed)
        #expect(vm.messages[0].message.id == 500)
    }

    @Test
    func sendInDraftConversationBackfillsConversationId() async {
        let repo = FakeMessageRepo()
        repo.sendResult = .success(srvMessage(id: 700, convId: 42, senderId: 3, body: "hi", tempId: "pending-X"))
        let vm = makeVM(
            route: .peer(peer),
            currentUserId: 3, repo: repo
        )
        #expect(vm.conversationId == nil)

        await vm.sendText("hi")

        #expect(vm.conversationId == 42)
        #expect(vm.messages[0].message.id == 700)
    }

    @Test
    func sendFailureMarksBubbleFailed() async {
        let repo = FakeMessageRepo()
        repo.sendResult = .failure(APIError.invalidResponse)
        let vm = makeVM(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 3, repo: repo
        )

        await vm.sendText("hi")

        #expect(vm.messages.count == 1)
        if case .failed = vm.messages[0].sendState { } else {
            Issue.record("expected .failed")
        }
    }

    @Test
    func retryFailedMessageResendsWithSameTempId() async {
        let repo = FakeMessageRepo()
        repo.sendResult = .failure(APIError.invalidResponse)
        let vm = makeVM(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 3, repo: repo
        )
        await vm.sendText("hi")
        #expect(vm.messages[0].sendState != .confirmed)
        let firstTempId = vm.messages[0].localId

        // 下一次服务端成功
        repo.sendResult = .success(srvMessage(id: 888, body: "hi", tempId: firstTempId))
        await vm.retry(localId: firstTempId)

        #expect(vm.messages[0].sendState == .confirmed)
        #expect(vm.messages[0].message.id == 888)
        #expect(repo.sendCalls.count == 2)
        // 两次用的是同一个 clientTempId——保证幂等去重 key 稳定
        #expect(repo.sendCalls[0].tempId == repo.sendCalls[1].tempId)
    }

    @Test
    func retryOnConfirmedIsNoOp() async {
        // 已确认消息上没有重试按钮；若被误调用也应无副作用
        let repo = FakeMessageRepo()
        repo.sendResult = .success(srvMessage(id: 1, body: "hi", tempId: "pending-X"))
        let vm = makeVM(
            route: .conversation(makeConversation(id: 5, peerId: 9)),
            currentUserId: 3, repo: repo
        )
        await vm.sendText("hi")
        let lid = vm.messages[0].localId
        await vm.retry(localId: lid)
        #expect(repo.sendCalls.count == 1)
    }

    private func makeConversation(id: Int, peerId: Int) -> Conversation {
        let json = """
        {
          "id": \(id),
          "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": \(peerId), "peer_username": "alice",
          "peer_display_name": null, "peer_avatar_url": null,
          "last_message_body": null, "last_message_type": null,
          "last_message_sender_id": null, "last_message_at": null,
          "last_read_message_id": null, "unread_count": 0
        }
        """.data(using: .utf8)!
        return try! APIClient.jsonDecoder.decode(Conversation.self, from: json)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`sendText` / `retry` 未定义。

- [ ] **Step 3：实现 send/retry**

在 `ChatViewModel` 里追加：

```swift
// MARK: - Send

func sendText(_ body: String) async {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard let token = tokenProvider() else { return }

    let tempId = makeTempId()
    let now = Date()
    let optimistic = Message(
        id: -Int.random(in: 1...Int.max),   // 本地占位 id；messages.id 只用于 confirmed 消息
        conversationId: conversationId ?? -1,
        senderId: currentUserId,
        body: trimmed, messageType: "text", mediaUrl: nil,
        createdAt: now, clientTempId: tempId
    )
    let localMsg = LocalMessage(
        localId: tempId, message: optimistic,
        sendState: .pending, localImageData: nil
    )
    messages.append(localMsg)

    await performSend(body: trimmed, tempId: tempId, token: token)
}

func retry(localId: String) async {
    guard let idx = messages.firstIndex(where: { $0.localId == localId }) else { return }
    guard case .failed = messages[idx].sendState else { return }
    guard let body = messages[idx].message.body else { return }
    guard let token = tokenProvider() else { return }

    // 翻回 pending
    messages[idx].sendState = .pending
    await performSend(body: body, tempId: localId, token: token)
}

private func performSend(body: String, tempId: String, token: String) async {
    do {
        let result = try await messageRepo.sendText(
            recipientId: peer.id, body: body, clientTempId: tempId, token: token
        )
        mergeServerResult(result, tempId: tempId)
    } catch {
        markFailed(tempId: tempId, error: error)
    }
}

/// 服务端 201 响应 / WS message.new 的 echo 都走这里；按 tempId 合并。
fileprivate func mergeServerResult(_ message: Message, tempId: String) {
    // 回填 draft conversation id
    if conversationId == nil {
        conversationId = message.conversationId
    }
    if let idx = messages.firstIndex(where: { $0.localId == tempId }) {
        messages[idx] = LocalMessage(
            localId: "id-\(message.id)",
            message: message,
            sendState: .confirmed,
            localImageData: messages[idx].localImageData
        )
    } else if !messages.contains(where: { $0.message.id == message.id }) {
        // WS echo 先到而本地没有 pending（理论不该发生，防御）
        messages.append(LocalMessage.confirmed(message))
    }
}

private func markFailed(tempId: String, error: Error) {
    guard let idx = messages.firstIndex(where: { $0.localId == tempId }) else { return }
    messages[idx].sendState = .failed(String(describing: error))
}
```

**设计说明**：
- `optimistic.id` 用负 Int 占位——后续 dedup 用的是 `localId` / `clientTempId`，`message.id` 只在 confirmed 时有意义。
- `mergeServerResult` 是 `fileprivate`——Task 10 的 WS 入口也要用它把 `message.new` 的 echo 合并进来。
- 失败态保留原 tempId；重试时 `performSend` 复用同一个 tempId，保持去重 key 稳定。
- **重试重复投递风险**（已知）：若第一次实际已落库，服务端没有幂等检查，第二次会产生重复行。作品集接受。

- [ ] **Step 4：运行测试确认通过**

```bash
$TEST
```

预期：5 个 send/retry 用例 + 前面 5 个 load 全绿。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
        ios-app/EchoIMTests/ChatViewModelSendTests.swift
git commit -m "feat(ios): add optimistic send, tempId merge, and retry"
```

---

## Task 10：ChatViewModel WS 事件接入（含草稿 promote）

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`
- Test: `ios-app/EchoIMTests/ChatViewModelWSTests.swift`

**动机：** 设计 §5.3 + §7.5：
1. `message.new` — 判重后 append；如果当前是**草稿态**且 `payload.sender_id == peerId`，把 `conversationId` 回填并走 `load()` 场景 A 拉最新（对方先激活了会话）
2. `conversation.updated` — 多设备已读游标同步（推进 `lastReadMessageId`，**P3 不聚合未读数到消息上**，留给 ConversationsListViewModel 处理）
3. `connection.ready` 之后的草稿 promote（§7.5 step 2）：ChatViewModel.onReady() 接口，拿到会话列表后扫一遍，若 `peer.id == self.peerId` 的 conversation 出现过，回填 + 补拉

**测试策略**：ChatViewModel 的 WS 入口是一个同步方法 `handleWSEvent(_ event: WSEvent)`，测试直接调它。真正订阅 + 解绑的路径（`wsClient.subscribe`）靠 View 层 onAppear/onDisappear 做，不归 VM 测。

- [ ] **Step 1：写 WS 测试**

`ios-app/EchoIMTests/ChatViewModelWSTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ChatViewModel — WS")
struct ChatViewModelWSTests {
    final class FakeMessageRepo: MessageRepository {
        var listResult: Result<[Message], Error> = .success([])
        var sendDelay: TimeInterval = 0
        var sendMessageId = 555
        private(set) var listCalls: [(Int, MessageCursor?)] = []
        func list(conversationId: Int, cursor: MessageCursor?, token: String) async throws -> [Message] {
            listCalls.append((conversationId, cursor))
            return try listResult.get()
        }
        func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
            if sendDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(sendDelay * 1_000_000_000))
            }
            return Message(
                id: sendMessageId, conversationId: 5, senderId: 3,
                body: body, messageType: "text", mediaUrl: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(sendMessageId)),
                clientTempId: clientTempId
            )
        }
    }

    private func msg(id: Int, convId: Int = 5, senderId: Int = 3, body: String = "hi", tempId: String? = nil) -> Message {
        Message(
            id: id, conversationId: convId, senderId: senderId,
            body: body, messageType: "text", mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
            clientTempId: tempId
        )
    }

    private func makeConversation(id: Int = 5, peerId: Int = 9) -> Conversation {
        let json = """
        { "id": \(id), "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": \(peerId), "peer_username": "alice",
          "peer_display_name": null, "peer_avatar_url": null,
          "last_message_body": null, "last_message_type": null,
          "last_message_sender_id": null, "last_message_at": null,
          "last_read_message_id": null, "unread_count": 0 }
        """.data(using: .utf8)!
        return try! APIClient.jsonDecoder.decode(Conversation.self, from: json)
    }

    @Test
    func incomingMessageFromPeerIsAppended() {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 9, messageRepo: repo, wsClient: nil,
            tokenProvider: { "jwt" }
        )
        vm.handleWSEvent(.messageNew(msg(id: 100, senderId: 3, body: "hey")))
        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].message.body == "hey")
        #expect(vm.messages[0].sendState == .confirmed)
    }

    @Test
    func ownEchoMergesWithPendingByClientTempId() async {
        let repo = FakeMessageRepo()
        repo.sendDelay = 0.05
        repo.sendMessageId = 555
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 3, messageRepo: repo, wsClient: nil,
            tokenProvider: { "jwt" }
        )

        let sendTask = Task { await vm.sendText("hi") }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let tempId = vm.messages[0].localId

        // WS echo 比 REST 响应先到：必须按 clientTempId 合并 pending，而不是追加第二条。
        vm.handleWSEvent(.messageNew(msg(id: 555, senderId: 3, body: "hi", tempId: tempId)))

        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].sendState == .confirmed)
        #expect(vm.messages[0].message.id == 555)

        await sendTask.value
        #expect(vm.messages.count == 1)
    }

    @Test
    func duplicateMessageIdIsIgnored() {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 9, messageRepo: repo, wsClient: nil,
            tokenProvider: { "jwt" }
        )
        let m = msg(id: 300)
        vm.handleWSEvent(.messageNew(m))
        vm.handleWSEvent(.messageNew(m))
        #expect(vm.messages.count == 1)
    }

    @Test
    func messageForDifferentConversationIsIgnored() {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .conversation(makeConversation(id: 5)),
            currentUserId: 9, messageRepo: repo, wsClient: nil,
            tokenProvider: { "jwt" }
        )
        vm.handleWSEvent(.messageNew(msg(id: 1, convId: 77, senderId: 3, body: "other chat")))
        #expect(vm.messages.isEmpty)
    }

    @Test
    func draftConversationActivatedByPeerMessage() async {
        // 草稿态：peer.id = 9；这时候对方先发了一条消息
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .peer(UserProfile(id: 9, username: "alice", displayName: nil, avatarUrl: nil)),
            currentUserId: 3, messageRepo: repo, wsClient: nil,
            tokenProvider: { "jwt" }
        )
        #expect(vm.conversationId == nil)

        vm.handleWSEvent(.messageNew(msg(id: 42, convId: 88, senderId: 9, body: "hello")))

        // conversationId 回填
        #expect(vm.conversationId == 88)
        // 消息被 append（身份对齐之后）
        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].message.body == "hello")
    }

    @Test
    func conversationUpdatedTracksLastReadMessageId() {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 9, messageRepo: repo, wsClient: nil,
            tokenProvider: { "jwt" }
        )
        #expect(vm.lastReadMessageId == nil)
        vm.handleWSEvent(.conversationUpdated(ConversationUpdatedPayload(conversationId: 5, lastReadMessageId: 99)))
        #expect(vm.lastReadMessageId == 99)
        // 再来一条更大的——推进
        vm.handleWSEvent(.conversationUpdated(ConversationUpdatedPayload(conversationId: 5, lastReadMessageId: 150)))
        #expect(vm.lastReadMessageId == 150)
        // 来一条更小的——忽略（已读游标只能前进）
        vm.handleWSEvent(.conversationUpdated(ConversationUpdatedPayload(conversationId: 5, lastReadMessageId: 80)))
        #expect(vm.lastReadMessageId == 150)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

- [ ] **Step 3：实现 handleWSEvent + lastReadMessageId + onReady**

在 `ChatViewModel` 里追加：

```swift
// MARK: - WS 状态

/// 服务端已确认的 last_read_message_id；多设备已读游标同步。P3 不基于它算未读，
/// 仅暴露给 UI 显示"已读/未读分隔线"等未来功能。
private(set) var lastReadMessageId: Int?

// MARK: - WS 订阅（View 层 onAppear 调）

private var subscription: WSSubscription?
private var readySubscription: WSSubscription?

func attachWSSubscription() {
    guard subscription == nil, let wsClient else { return }
    subscription = wsClient.subscribe { [weak self] event in
        self?.handleWSEvent(event)
    }
    readySubscription = wsClient.onReady { [weak self] in
        Task { await self?.handleWSReady() }
    }
}

func detachWSSubscription() {
    subscription?.cancel()
    subscription = nil
    readySubscription?.cancel()
    readySubscription = nil
}

// MARK: - WS 事件分发

func handleWSEvent(_ event: WSEvent) {
    switch event {
    case .messageNew(let message):
        handleIncomingMessage(message)
    case .conversationUpdated(let p):
        handleConversationUpdated(p)
    default:
        // typing / presence / friend_request / unknown → P3 不处理
        return
    }
}

private func handleIncomingMessage(_ incoming: Message) {
    // 草稿态：对方先发了消息 → 回填 conversationId 并把这条消息录入
    if conversationId == nil {
        if incoming.senderId == peer.id {
            conversationId = incoming.conversationId
        } else {
            // 草稿态下收到别的会话消息，或自己在别处发送的 echo——这里都忽略
            return
        }
    }

    // 非当前会话 → 忽略
    guard incoming.conversationId == conversationId else { return }

    // 自己发的 echo：按 clientTempId 合并 pending
    if let tempId = incoming.clientTempId, incoming.senderId == currentUserId {
        mergeServerResult(incoming, tempId: tempId)
        return
    }

    // 普通 append + 判重
    if messages.contains(where: { $0.message.id == incoming.id }) { return }
    messages.append(.confirmed(incoming))
}

private func handleConversationUpdated(_ p: ConversationUpdatedPayload) {
    guard p.conversationId == conversationId else { return }
    let current = lastReadMessageId ?? 0
    // 已读游标单调递增——老的 WS 事件不能回退
    if p.lastReadMessageId > current {
        lastReadMessageId = p.lastReadMessageId
    }
}

private func handleWSReady() async {
    if conversationId == nil {
        guard let token = tokenProvider(), let conversationRepository else { return }
        do {
            let conversations = try await conversationRepository.list(token: token)
            await reconcileAfterReconnect(conversations: conversations)
        } catch {
            // 草稿 promote 失败不影响当前聊天页，下一次 ready / 手动重进会再补。
        }
    } else {
        await refetchMissedMessages()
    }
}

// MARK: - Reconnect hook

/// 收到 connection.ready 后，如果草稿态且对应 peer 的会话已经在会话列表里出现过，
/// 回填 conversationId 并走 load()。`handleWSReady()` 会先 GET /conversations 再把列表交给这里。
/// 设计文档 §7.5 step 2。
func reconcileAfterReconnect(conversations: [Conversation]) async {
    guard conversationId == nil else {
        // 非草稿态 → 走 Task 9 的 §5.3 场景 C（after cursor 补拉）
        await refetchMissedMessages()
        return
    }
    if let match = conversations.first(where: { $0.peer.id == peer.id }) {
        conversationId = match.id
        await load()
    }
}

/// §5.3 场景 C 的 P3 精简版：after cursor 补拉；P4 会改成连续后缀不变式的完整形态。
/// P3 不做"满页循环翻页"——单次 list(after:) 足够覆盖绝大多数断线片段；极端情况
/// 下丢一小段历史消息由用户上滑分页补回来。
func refetchMissedMessages() async {
    guard let convId = conversationId else { return }
    guard let token = tokenProvider() else { return }
    // 找当前已确认消息里最大的 id
    let newest = messages.reduce(into: 0) { acc, lm in
        if case .confirmed = lm.sendState {
            acc = max(acc, lm.message.id)
        }
    }
    guard newest > 0 else {
        await load()
        return
    }
    do {
        let rows = try await messageRepo.list(
            conversationId: convId, cursor: .after(newest), token: token
        )
        // after 返回 ASC；直接 append 判重
        for m in rows {
            if !messages.contains(where: { $0.message.id == m.id }) {
                messages.append(.confirmed(m))
            }
        }
    } catch {
        // ignore；下一次 reconnect 或 UI 重进 view 会再补
    }
}
```

别漏了同步修改 `init(route:...)` 的 `.conversation` 分支，把会话列表带来的初始游标带进来：

```swift
case .conversation(let conv):
    self.conversationId = conv.id
    self.peer = conv.peer
    self.lastReadMessageId = conv.lastReadMessageId
```

- [ ] **Step 4：运行测试确认通过**

```bash
$TEST
```

预期：6 个 WS 用例 + 前面 10 个共 16 个 ChatViewModel 用例全绿。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
        ios-app/EchoIMTests/ChatViewModelWSTests.swift
git commit -m "feat(ios): handle WS messageNew/conversationUpdated and draft promote"
```

---


## Task 11：ChatViewModel 进入会话标已读

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`
- Modify: `ios-app/EchoIM/Features/Chat/MessageRepository.swift`
- Modify: `ios-app/EchoIMTests/MessageRepositoryTests.swift`
- Test: `ios-app/EchoIMTests/ChatViewModelReadTests.swift`

**动机：** 进入会话时（有消息）把最新消息 id 作为 `last_read_message_id` PUT 给服务端。服务端 `GREATEST` 保证只能前进（设计 §5.2 / 键点速查）。客户端做两件事：
1. 进入 / 收到新消息后推进本地 `lastReadMessageId` 的打算值
2. 调用 `PUT /conversations/:id/read` 前先做本地短路：没有消息、草稿态、或游标已经推进过时都不重复请求

- [ ] **Step 1：MessageRepository 加 markRead**

编辑 `ios-app/EchoIM/Features/Chat/MessageRepository.swift`，在 protocol 里追加：

```swift
func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws
```

在 `SendTextBody` 下方追加：

```swift
private struct MarkReadBody: Encodable {
    let lastReadMessageId: Int
    enum CodingKeys: String, CodingKey {
        case lastReadMessageId = "last_read_message_id"
    }
}
```

在 `MessageRepositoryImpl` 里追加：

```swift
func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {
    let _: EmptyResponse = try await api.request(
        Endpoints.Conversations.read(conversationId: conversationId),
        method: "PUT",
        token: token,
        body: MarkReadBody(lastReadMessageId: lastReadMessageId)
    )
}
```

同步补齐前面测试里的 `FakeMessageRepo`，否则协议新增方法后旧测试会编译失败：

```swift
func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
```

需要加到 `ChatViewModelLoadTests`、`ChatViewModelSendTests`、`ChatViewModelWSTests` 里的 fake repo。

**注意**：`PUT /conversations/:id/read` 的响应 body 是 `{ last_read_message_id: Int }`，不是 204 空。用 `EmptyResponse` 会 decode 成功（服务端 body 会被忽略），但更严谨的写法是定义返回 struct 并丢弃。P3 走 EmptyResponse 节省一个类型——客户端不需要回包里的字段（已在 WS `conversation.updated` 里拿到）。

**看 APIClient.request 的实现**——它对 `Response.self == EmptyResponse.self` 做了特判（`APIClient.swift:105`），直接返回空实例而不尝试 decode。所以不论 body 是否空，`EmptyResponse` 都是安全的。

- [ ] **Step 2：MessageRepositoryTests 补 markRead 用例**

编辑 `ios-app/EchoIMTests/MessageRepositoryTests.swift`，在最后一个 test 后追加：

```swift
@Test func markReadPutsSnakeCaseBody() async throws {
    var capturedMethod: String?
    var capturedPath: String?
    var capturedBody: Data?
    let (config, _) = MockURLProtocol.configure { req in
        capturedMethod = req.httpMethod
        capturedPath = req.url?.path
        if let stream = req.httpBodyStream { capturedBody = Data(reading: stream) }
        else { capturedBody = req.httpBody }
        return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "{\"last_read_message_id\":200}".data(using: .utf8)!)
    }
    let repo = MessageRepositoryImpl(api: APIClient(session: URLSession(configuration: config)))
    try await repo.markRead(conversationId: 5, lastReadMessageId: 200, token: "jwt")

    #expect(capturedMethod == "PUT")
    #expect(capturedPath == "/api/conversations/5/read")
    let dict = try JSONSerialization.jsonObject(with: capturedBody ?? Data()) as? [String: Any]
    #expect(dict?["last_read_message_id"] as? Int == 200)
}
```

- [ ] **Step 3：写 ChatViewModel.markReadIfNeeded 失败测试**

`ios-app/EchoIMTests/ChatViewModelReadTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ChatViewModel — mark read")
struct ChatViewModelReadTests {
    final class FakeMessageRepo: MessageRepository {
        var listResult: Result<[Message], Error> = .success([])
        private(set) var markCalls: [(convId: Int, id: Int)] = []
        func list(conversationId: Int, cursor: MessageCursor?, token: String) async throws -> [Message] {
            try listResult.get()
        }
        func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
            throw APIError.invalidResponse
        }
        func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {
            markCalls.append((conversationId, lastReadMessageId))
        }
    }

    private func makeConversation(id: Int = 5, peerId: Int = 9, lastReadMessageId: Int? = nil) -> Conversation {
        let lastRead = lastReadMessageId.map(String.init) ?? "null"
        let json = """
        { "id": \(id), "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": \(peerId), "peer_username": "alice",
          "peer_display_name": null, "peer_avatar_url": null,
          "last_message_body": null, "last_message_type": null,
          "last_message_sender_id": null, "last_message_at": null,
          "last_read_message_id": \(lastRead), "unread_count": 0 }
        """.data(using: .utf8)!
        return try! APIClient.jsonDecoder.decode(Conversation.self, from: json)
    }

    private func msg(id: Int, senderId: Int = 3) -> Message {
        Message(
            id: id, conversationId: 5, senderId: senderId,
            body: "hi", messageType: "text", mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
            clientTempId: nil
        )
    }

    @Test
    func markReadSendsLatestConfirmedMessageId() async {
        let repo = FakeMessageRepo()
        repo.listResult = .success([msg(id: 3), msg(id: 2), msg(id: 1)])
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 9,
            messageRepo: repo, wsClient: nil,
            tokenProvider: { "jwt" }
        )
        await vm.load()
        await vm.markReadIfNeeded()
        #expect(repo.markCalls.count == 1)
        #expect(repo.markCalls[0].id == 3)
    }

    @Test
    func markReadIsNoOpOnEmptyMessages() async {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 9,
            messageRepo: repo, wsClient: nil,
            tokenProvider: { "jwt" }
        )
        await vm.markReadIfNeeded()
        #expect(repo.markCalls.isEmpty)
    }

    @Test
    func markReadSkipsWhenCursorAlreadyAdvanced() async {
        // lastReadMessageId 已经 ≥ 当前最大 id → 无需重复打点
        let repo = FakeMessageRepo()
        repo.listResult = .success([msg(id: 3), msg(id: 2), msg(id: 1)])
        let vm = ChatViewModel(
            route: .conversation(makeConversation(lastReadMessageId: 3)),
            currentUserId: 9,
            messageRepo: repo, wsClient: nil,
            tokenProvider: { "jwt" }
        )
        await vm.load()

        await vm.markReadIfNeeded()
        #expect(repo.markCalls.isEmpty)
    }

    @Test
    func markReadSkipsForDraftConversation() async {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .peer(UserProfile(id: 9, username: "a", displayName: nil, avatarUrl: nil)),
            currentUserId: 3,
            messageRepo: repo, wsClient: nil,
            tokenProvider: { "jwt" }
        )
        await vm.markReadIfNeeded()
        #expect(repo.markCalls.isEmpty)
    }
}
```

- [ ] **Step 4：运行测试确认失败**

```bash
$TEST
```

- [ ] **Step 5：实现 markReadIfNeeded**

在 `ChatViewModel` 里追加：

```swift
// MARK: - Mark read

func markReadIfNeeded() async {
    guard let convId = conversationId else { return }
    guard let token = tokenProvider() else { return }
    // 找当前已确认的最大 id
    let latest = messages.reduce(into: 0) { acc, lm in
        if case .confirmed = lm.sendState {
            acc = max(acc, lm.message.id)
        }
    }
    guard latest > 0 else { return }
    guard latest > (lastReadMessageId ?? 0) else { return }

    do {
        try await messageRepo.markRead(
            conversationId: convId, lastReadMessageId: latest, token: token
        )
        // 乐观推进本地游标；WS `conversation.updated` 回来也会推进（只增不减，idempotent）
        lastReadMessageId = latest
    } catch {
        // 静默失败；下次 markReadIfNeeded（新消息到达或切入切出）重试
    }
}
```

**关于重复请求**：P3 不做定时器去抖，只在两个时点调用：
1. `load()` 完成后（onAppear）
2. 新的 peer 消息通过 `message.new` 到达后

把这两个调用点加到 `load()` 与 `handleIncomingMessage` 末尾：

编辑 `ChatViewModel.load()` 的 `phase = .loaded` 之后：

```swift
// 进入页面立刻标一次已读
await markReadIfNeeded()
```

编辑 `handleIncomingMessage` 末尾（append 之后）：

```swift
// 收到对方消息后立刻推进已读
if incoming.senderId != currentUserId {
    Task { [weak self] in
        await self?.markReadIfNeeded()
    }
}
```

**说明**：`markReadIfNeeded` 有"相同 id 不重发"的短路（`latest > (lastReadMessageId ?? 0)`）。快速连续收到 N 条消息时仍可能打多次 PUT（因为 `handleIncomingMessage` 是同步入口），但服务端 `GREATEST` 保证语义正确，作品集范围接受。

- [ ] **Step 6：运行测试**

```bash
$TEST
```

预期：MessageRepository 5 个（含新加的 markRead）+ ChatViewModelRead 4 个 + 前面 ChatViewModel 16 个 + 原有全部绿。

- [ ] **Step 7：提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
        ios-app/EchoIM/Features/Chat/MessageRepository.swift \
        ios-app/EchoIMTests/MessageRepositoryTests.swift \
        ios-app/EchoIMTests/ChatViewModelReadTests.swift
git commit -m "feat(ios): mark conversation as read on enter and incoming peer message"
```

---

## Task 12：ChatView + MessageBubble + 导航接入

**Files:**
- Create: `ios-app/EchoIM/Features/Chat/ChatView.swift`
- Create: `ios-app/EchoIM/Features/Chat/MessageBubble.swift`
- Modify: `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/FriendsListView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/ContactsView.swift`

**动机：** 把 ChatViewModel 接到 SwiftUI 上，并把 ConversationsListView 和 FriendsListView 的 row 改成 `NavigationLink(value: ChatRoute)`；通过 `.navigationDestination(for: ChatRoute.self)` 构造 ChatView。

- [ ] **Step 1：MessageBubble**

`ios-app/EchoIM/Features/Chat/MessageBubble.swift`：

```swift
import SwiftUI

struct MessageBubble: View {
    let message: LocalMessage
    let isSelf: Bool
    var onRetry: () -> Void = {}

    var body: some View {
        HStack {
            if isSelf { Spacer(minLength: 40) }
            VStack(alignment: isSelf ? .trailing : .leading, spacing: 4) {
                bubble
                footer
            }
            if !isSelf { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        Text(message.message.body ?? "")
            .font(.body)
            .foregroundStyle(isSelf ? .white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelf ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
            )
            .opacity(message.sendState == .pending ? 0.65 : 1.0)
    }

    @ViewBuilder
    private var footer: some View {
        switch message.sendState {
        case .confirmed:
            EmptyView()
        case .pending:
            Text("发送中…").font(.caption2).foregroundStyle(.secondary)
        case .failed:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("发送失败").font(.caption2).foregroundStyle(.red)
                Button("重试", action: onRetry)
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }
}
```

- [ ] **Step 2：ChatView**

`ios-app/EchoIM/Features/Chat/ChatView.swift`：

```swift
import SwiftUI

struct ChatView: View {
    @State private var vm: ChatViewModel
    @State private var draft: String = ""

    init(
        route: ChatRoute,
        currentUserId: Int,
        messageRepo: MessageRepository,
        wsClient: WebSocketClient?,
        conversationRepository: ConversationRepository? = nil,
        tokenProvider: @escaping @MainActor () -> String?
    ) {
        _vm = State(wrappedValue: ChatViewModel(
            route: route,
            currentUserId: currentUserId,
            messageRepo: messageRepo,
            wsClient: wsClient,
            conversationRepository: conversationRepository,
            tokenProvider: tokenProvider
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            Divider()
            inputBar
        }
        .navigationTitle(vm.peer.displayName ?? vm.peer.username)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            vm.attachWSSubscription()
            await vm.load()
        }
        .onDisappear {
            vm.detachWSSubscription()
        }
    }

    @ViewBuilder
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if vm.hasMoreOlder {
                        Button {
                            Task { await vm.loadOlder() }
                        } label: {
                            if vm.isLoadingOlder {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("加载更多").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 8)
                    }
                    ForEach(vm.messages) { lm in
                        MessageBubble(
                            message: lm,
                            isSelf: lm.message.senderId == selfId,
                            onRetry: { Task { await vm.retry(localId: lm.localId) } }
                        )
                        .id(lm.localId)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: vm.messages.last?.localId) { _, newLast in
                // 来新消息时滚到底
                if let newLast {
                    withAnimation(.easeOut) {
                        proxy.scrollTo(newLast, anchor: .bottom)
                    }
                }
            }
            .accessibilityIdentifier("chatMessages")
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("说点什么…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("chatInput")

            Button {
                let body = draft
                draft = ""
                Task { await vm.sendText(body) }
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(canSend ? Color.accentColor : Color.gray, in: Circle())
            }
            .disabled(!canSend)
            .accessibilityIdentifier("chatSend")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selfId: Int {
        // ChatViewModel 的 currentUserId 是 private；为了 bubble 判断 isSelf，ChatViewModel
        // 需要暴露。下一步在 VM 里把 currentUserId 改为 `let currentUserId: Int` 并加 `private(set)`
        // 或直接 `let`。此处先按已暴露写——Task 12 Step 4 会同步把 VM 改动提交。
        vm.currentUserId
    }
}
```

- [ ] **Step 3：把 ChatViewModel.currentUserId 暴露为 `let`**

编辑 `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`，把：

```swift
private let currentUserId: Int
```

改成：

```swift
let currentUserId: Int
```

- [ ] **Step 4：ConversationsListView 接导航**

编辑 `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`，把 list 的 List 包一层 NavigationLink：

找到 `private var list: some View {` 的实现，把：

```swift
private var list: some View {
    List(vm.conversations) { c in
        ConversationRow(conversation: c)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }
    .listStyle(.plain)
    .accessibilityIdentifier("conversationsList")
}
```

改成：

```swift
private var list: some View {
    List(vm.conversations) { c in
        NavigationLink(value: ChatRoute.conversation(c)) {
            ConversationRow(conversation: c)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }
    .listStyle(.plain)
    .accessibilityIdentifier("conversationsList")
}
```

然后在 `NavigationStack { ... }` 块里（ConversationsListView 的 body）加 `.navigationDestination`：

```swift
var body: some View {
    NavigationStack {
        content
            .navigationTitle("聊天")
            .refreshable { await vm.refresh() }
            .task { await vm.load() }
            .navigationDestination(for: ChatRoute.self) { route in
                destination(for: route)
            }
    }
}

@ViewBuilder
private func destination(for route: ChatRoute) -> some View {
    ChatView(
        route: route,
        currentUserId: currentUserId,
        messageRepo: messageRepo,
        wsClient: wsClient,
        conversationRepository: conversationRepo,
        tokenProvider: tokenProvider
    )
}
```

这需要 ConversationsListView 的 init 追加 `currentUserId` / `messageRepo` / `wsClient` 参数。编辑 init：

```swift
init(
    repository: ConversationRepository,
    messageRepo: MessageRepository,
    wsClient: WebSocketClient?,
    currentUserId: Int,
    tokenProvider: @escaping @MainActor () -> String?
) {
    _vm = State(wrappedValue: ConversationsListViewModel(
        repository: repository,
        tokenProvider: tokenProvider
    ))
    self.messageRepo = messageRepo
    self.conversationRepo = repository
    self.wsClient = wsClient
    self.currentUserId = currentUserId
    self.tokenProvider = tokenProvider
}

private let conversationRepo: ConversationRepository
private let messageRepo: MessageRepository
private let wsClient: WebSocketClient?
private let currentUserId: Int
private let tokenProvider: () -> String?
```

**注意**：`ConversationsListView` 原先的 `tokenProvider` 只给 VM 用，现在 ChatView 也要用——在 init 里保留一份。

- [ ] **Step 5：FriendsListView row 改成 NavigationLink**

编辑 `ios-app/EchoIM/Features/Contacts/FriendsListView.swift`，把 List 中的 HStack row 包一层：

```swift
List(friends) { friend in
    NavigationLink(value: ChatRoute.peer(friend)) {
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
    }
    .listRowSeparator(.hidden)
}
.listStyle(.plain)
.accessibilityElement(children: .contain)
.accessibilityIdentifier("friendsList")
```

- [ ] **Step 6：ContactsView 加 navigationDestination**

编辑 `ios-app/EchoIM/Features/Contacts/ContactsView.swift`，在 `NavigationStack` body 的 `.sheet` 前追加（与 ConversationsListView 对称）：

```swift
.navigationDestination(for: ChatRoute.self) { route in
    ChatView(
        route: route,
        currentUserId: currentUserId,
        messageRepo: messageRepo,
        wsClient: wsClient,
        conversationRepository: conversationRepo,
        tokenProvider: tokenProvider
    )
}
```

并给 ContactsView 的 init 追加四个依赖：`currentUserId: Int, messageRepo: MessageRepository, conversationRepo: ConversationRepository, wsClient: WebSocketClient?`。完整 init：

```swift
init(
    friendRepo: FriendRepository,
    requestRepo: FriendRequestRepository,
    userRepo: UserRepository,
    messageRepo: MessageRepository,
    conversationRepo: ConversationRepository,
    wsClient: WebSocketClient?,
    currentUserId: Int,
    tokenProvider: @escaping () -> String?
) {
    _vm = State(wrappedValue: ContactsViewModel(
        friendRepo: friendRepo,
        requestRepo: requestRepo,
        tokenProvider: tokenProvider
    ))
    self.userRepo = userRepo
    self.messageRepo = messageRepo
    self.conversationRepo = conversationRepo
    self.wsClient = wsClient
    self.currentUserId = currentUserId
    self.tokenProvider = tokenProvider
}

private let userRepo: UserRepository
private let messageRepo: MessageRepository
private let conversationRepo: ConversationRepository
private let wsClient: WebSocketClient?
private let currentUserId: Int
private let tokenProvider: () -> String?
```

- [ ] **Step 7：MainTabView 传入新依赖**

编辑 `ios-app/EchoIM/Features/Main/MainTabView.swift`，把 chatsTab / contactsTab 改为：

```swift
private var chatsTab: some View {
    ConversationsListView(
        repository: container.makeConversationRepository(),
        messageRepo: container.makeMessageRepository(),
        wsClient: container.wsClient,
        currentUserId: container.currentUser?.id ?? 0,
        tokenProvider: { [tokenStore = container.tokenStore] in
            (try? tokenStore.load())?.token
        }
    )
}

private var contactsTab: some View {
    ContactsView(
        friendRepo: container.makeFriendRepository(),
        requestRepo: container.makeFriendRequestRepository(),
        userRepo: container.makeUserRepository(),
        messageRepo: container.makeMessageRepository(),
        conversationRepo: container.makeConversationRepository(),
        wsClient: container.wsClient,
        currentUserId: container.currentUser?.id ?? 0,
        tokenProvider: { [tokenStore = container.tokenStore] in
            (try? tokenStore.load())?.token
        }
    )
}
```

**关于 currentUserId 为 0 的情况**：只有在 `currentUser == nil`（未登录）时 MainTabView 不会被渲染（RootView 分支判断），所以这里 `?? 0` 实际上不会走到。但类型上必须给默认值，留 0 作为无效哨兵。

**关于 `container.wsClient` 传入时的持有语义**：WebSocketClient 是 AppContainer 的 `var`，MainTabView.body 每次重算都会重新读取 —— 如果这期间 `wsClient` 被设为 nil（登出时），ChatViewModel 里的 `weak var wsClient` 会自动清空。**但** `ConversationsListView`/`ContactsView` 的 init 只捕获第一次的值并存进 `_vm = State(wrappedValue: ...)`，重算不会重新传递——这正符合 Task 9 VM 所有权设计。ChatViewModel 里持有的也是 weak 引用，AppContainer 释放后 ChatViewModel 里的 wsClient 变 nil，后续 `attachWSSubscription()` 会 no-op。

- [ ] **Step 8：编译 + 测试**

```bash
$BUILD
$TEST
```

预期：全绿。如果有 P2 的 MainTabView 相关 smoke 因依赖签名变化而挂（UI 测试通常不直接依赖 init 签名），重新跑一遍即可。

- [ ] **Step 9：提交**

```bash
git add ios-app/EchoIM/Features/Chat/ \
        ios-app/EchoIM/Features/Conversations/ConversationsListView.swift \
        ios-app/EchoIM/Features/Contacts/FriendsListView.swift \
        ios-app/EchoIM/Features/Contacts/ContactsView.swift \
        ios-app/EchoIM/Features/Main/MainTabView.swift
git commit -m "feat(ios): add ChatView with bubbles and wire navigation from lists"
```

---

## Task 13：ConversationsListViewModel WS 接入

**Files:**
- Modify: `ios-app/EchoIM/Features/Conversations/ConversationsListViewModel.swift`

**动机：** 设计 §8 P3：`ChatsList 接 WS 更新`。订阅 `message.new` 和 `conversation.updated`：
- `message.new` 到达 → 找到对应 `conversation_id` 的 row → 更新 `last_message_*` + 未读数 + 重排序（按 `last_message_at`）；新会话直接触发 `refresh()` 全拉一次（peer 信息要从服务端带回）
- `conversation.updated` 到达 → 推进该 row 的 `last_read_message_id`，重算未读数
- 重连后（`wsClient.state` 回到 `.ready`）→ 主动 refresh 一次会话列表（§7.5 step 1）

**P3 策略简化**：本阶段**不**订阅 `friend_request.*`（让 ContactsView 保留 P2 的 `.refreshable` 被动刷新即可）；P6+ 再接。

- [ ] **Step 1：扩充 ConversationsListViewModel**

编辑 `ios-app/EchoIM/Features/Conversations/ConversationsListViewModel.swift`，增加 WS 订阅字段和处理。完整文件：

```swift
import Foundation
import Observation

enum ConversationsPhase: Equatable, CustomStringConvertible {
    case idle
    case loading
    case loaded
    case unauthenticated
    case error(String)

    var description: String {
        switch self {
        case .idle:             "idle"
        case .loading:          "loading"
        case .loaded:           "loaded"
        case .unauthenticated:  "unauthenticated"
        case .error(let m):     "error(\(m))"
        }
    }
}

@Observable
@MainActor
final class ConversationsListViewModel {
    private(set) var conversations: [Conversation] = []
    private(set) var phase: ConversationsPhase = .idle

    private let repository: ConversationRepository
    private let tokenProvider: () -> String?
    private let currentUserId: () -> Int?
    private weak var wsClient: WebSocketClient?
    private var wsSubscription: WSSubscription?

    init(
        repository: ConversationRepository,
        tokenProvider: @escaping () -> String?,
        currentUserId: @escaping () -> Int? = { nil },
        wsClient: WebSocketClient? = nil
    ) {
        self.repository = repository
        self.tokenProvider = tokenProvider
        self.currentUserId = currentUserId
        self.wsClient = wsClient
    }

    // MARK: - Load

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

    // MARK: - WS subscription

    func attachWSSubscription() {
        guard wsSubscription == nil, let wsClient else { return }
        wsSubscription = wsClient.subscribe { [weak self] event in
            self?.handleWSEvent(event)
        }
    }

    func detachWSSubscription() {
        wsSubscription?.cancel()
        wsSubscription = nil
    }

    func handleWSEvent(_ event: WSEvent) {
        switch event {
        case .messageNew(let m):
            applyIncomingMessage(m)
        case .conversationUpdated(let p):
            applyConversationUpdated(p)
        default:
            return
        }
    }

    private func applyIncomingMessage(_ m: Message) {
        let selfId = currentUserId() ?? 0
        guard let idx = conversations.firstIndex(where: { $0.id == m.conversationId }) else {
            // 新会话：全量刷一次获取 peer 信息
            Task { await refresh() }
            return
        }
        let old = conversations[idx]
        // 只把"id > 自己已读游标"的对方消息计入未读
        let incrementUnread =
            m.senderId != selfId && m.id > (old.lastReadMessageId ?? 0)
        let updated = Conversation.updatedCopy(
            of: old,
            lastMessageBody: m.body,
            lastMessageType: m.messageType,
            lastMessageSenderId: m.senderId,
            lastMessageAt: m.createdAt,
            unreadCount: old.unreadCount + (incrementUnread ? 1 : 0)
        )
        var next = conversations
        next.remove(at: idx)
        // 按 last_message_at DESC 重排：新条目一定是最新的，直接放到最前
        next.insert(updated, at: 0)
        conversations = next
    }

    private func applyConversationUpdated(_ p: ConversationUpdatedPayload) {
        guard let idx = conversations.firstIndex(where: { $0.id == p.conversationId }) else {
            return
        }
        let old = conversations[idx]
        guard p.lastReadMessageId > (old.lastReadMessageId ?? 0) else { return }
        // 简单实现：推进 lastReadMessageId；未读数无法精确重算（需要消息列表在手），
        // 先乐观清零（P3 接受）。WS 后端在已读推进时本来就只广播给自己，所以 unread 清零通常正确。
        conversations[idx] = Conversation.updatedCopy(
            of: old,
            lastReadMessageId: p.lastReadMessageId,
            unreadCount: 0
        )
    }
}

// MARK: - Conversation 局部更新辅助

extension Conversation {
    /// Conversation 是 let-only struct；WS 到达时我们只想改几个字段。
    /// 一次声明成一个辅助函数，避免 viewModel 处满屏 `Conversation(id: ..., created_at: ..., ...)`。
    static func updatedCopy(
        of c: Conversation,
        lastMessageBody: String? = nil,
        lastMessageType: String? = nil,
        lastMessageSenderId: Int? = nil,
        lastMessageAt: Date? = nil,
        lastReadMessageId: Int? = nil,
        unreadCount: Int? = nil
    ) -> Conversation {
        Conversation(
            id: c.id,
            createdAt: c.createdAt,
            peer: c.peer,
            lastMessageBody: lastMessageBody ?? c.lastMessageBody,
            lastMessageType: lastMessageType ?? c.lastMessageType,
            lastMessageSenderId: lastMessageSenderId ?? c.lastMessageSenderId,
            lastMessageAt: lastMessageAt ?? c.lastMessageAt,
            lastReadMessageId: lastReadMessageId ?? c.lastReadMessageId,
            unreadCount: unreadCount ?? c.unreadCount
        )
    }
}
```

**关于 Conversation 的 memberwise init**：目前 `Conversation` 没有显式 memberwise init，但 struct 自动合成（除非加了 `extension` 里的自定义 init）。当前代码里 `Conversation` 只有 `init(from decoder:)` 在 extension 里——extension 里的 init **不会**阻止编译器合成 memberwise init。所以上面直接调 `Conversation(id:..., peer:..., ...)` 应该能编译通过。如果不行，把 memberwise init 显式写到类型本体里（Task 13 Step 1 的编辑里可以顺手加）。

- [ ] **Step 2：ConversationsListView 接 VM 新参数 + 在 task 里 attach 订阅**

编辑 `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`，改 init：

```swift
init(
    repository: ConversationRepository,
    messageRepo: MessageRepository,
    wsClient: WebSocketClient?,
    currentUserId: Int,
    tokenProvider: @escaping @MainActor () -> String?
) {
    _vm = State(wrappedValue: ConversationsListViewModel(
        repository: repository,
        tokenProvider: tokenProvider,
        currentUserId: { currentUserId },
        wsClient: wsClient
    ))
    self.messageRepo = messageRepo
    self.wsClient = wsClient
    self.currentUserId = currentUserId
    self.tokenProvider = tokenProvider
}
```

并在 `.task { await vm.load() }` 改成：

```swift
.task {
    vm.attachWSSubscription()
    await vm.load()
}
.onDisappear {
    // NavigationStack 下 ConversationsListView 通常不会 disappear（它是 tab root），
    // 但保留对称 detach，防止未来重构时忘记
    vm.detachWSSubscription()
}
```

- [ ] **Step 3：补加重连后全量刷新**

RootView 在 `.onChange(of: scenePhase)` 前台恢复时已经调了 `wsClient?.connectIfNeeded()`。重连成功后 ConversationsListViewModel 也应该全刷一次（§7.5 step 1）。Task 4 已经给 `WebSocketClient` 加了 `onReady` 回调，这里直接订阅即可。

编辑 `ConversationsListViewModel.attachWSSubscription()`，追加：

```swift
private var readySubscription: WSSubscription?

func attachWSSubscription() {
    guard wsSubscription == nil, let wsClient else { return }
    wsSubscription = wsClient.subscribe { [weak self] event in
        self?.handleWSEvent(event)
    }
    readySubscription = wsClient.onReady { [weak self] in
        // §7.5 step 1：重连成功先刷会话列表
        Task { await self?.refresh() }
    }
}

func detachWSSubscription() {
    wsSubscription?.cancel()
    wsSubscription = nil
    readySubscription?.cancel()
    readySubscription = nil
}
```

**为什么不放到 AppContainer 上？** `ChatViewModel` 和 `ConversationsListViewModel` 对 ready 的反应不同：聊天页补拉 / 草稿 promote，会话列表全量刷新。每个 VM 各自订阅 `onReady` 比 AppContainer 集中协调更简单。

- [ ] **Step 4：编译 + 测试**

```bash
$BUILD
$TEST
```

P1/P2 的 `ConversationsListViewModelTests` 用到的 init 签名变了——补默认值（`currentUserId: { nil }, wsClient: nil`）兼容，应能保留原有断言。检查 test 代码：

```swift
let vm = ConversationsListViewModel(
    repository: FakeRepo(.success([c1])),
    tokenProvider: { "jwt" }
)
```

因为新 init 给 `currentUserId` / `wsClient` 都带了默认值，原代码无需修改直接通过。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Features/Conversations/
git commit -m "feat(ios): wire WS events and ready refresh into conversations list"
```

---

## Task 14：XCUITest Chat smoke + README 更新

**Files:**
- Create: `ios-app/EchoIMUITests/ChatSmokeTests.swift`
- Modify: `ios-app/EchoIM/Features/Chat/ChatView.swift`（为 UI smoke 暴露稳定 accessibility identifiers）
- Modify: `ios-app/README.md`

**动机：** 一个最低限度的端到端 smoke——登录 → 会话列表（需有一条 A↔B 的会话）→ 点进 → 输入一条文字 → 点发送 → 列表预览更新。用于防止 P4+ 改动把 P3 路径打坏。

**前提**：后端 + 测试账号 A（`smoke@test.local` / `password123`）且 A 与某个 B 用户已互为好友且已有至少一条历史消息。如果本地环境没有，新注册一个 `smoke2@test.local` 账号互加并发一条，然后回到 A 账号跑 smoke；或在本地开发 DB 里给 `smoke@test.local` seed 一条 accepted friend + conversation + message。CI 环境要固定准备这条 seed 数据。

- [ ] **Step 1：给 ChatView 输入框和发送按钮加稳定 UI 测试标识**

编辑 `ios-app/EchoIM/Features/Chat/ChatView.swift`，在输入框和发送按钮上追加：

```swift
.accessibilityIdentifier("chatInput")
```

```swift
.accessibilityIdentifier("chatSend")
```

**注意**：`TextField(..., axis: .vertical)` 在 XCUITest 里可能暴露为 `TextView` 而不是普通 `TextField`，所以 smoke 里不要用 `app.textFields["chatInput"]` 定位。

- [ ] **Step 2：写 ChatSmokeTests**

`ios-app/EchoIMUITests/ChatSmokeTests.swift`：

```swift
import XCTest

final class ChatSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSendTextMessage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-keychain"]
        app.launch()

        // 登录
        let email = app.textFields["loginEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("smoke@test.local")

        let password = app.secureTextFields["loginPassword"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("password123")

        app.buttons["loginSubmit"].tap()

        // 落在聊天 tab
        let tabView = app.otherElements["mainTabView"]
        XCTAssertTrue(tabView.waitForExistence(timeout: 10))

        let convList = app.descendants(matching: .any)["conversationsList"]
        XCTAssertTrue(convList.waitForExistence(timeout: 10))

        // 点第一行会话进入 ChatView（假设 smoke 账号必有一条会话）
        let firstRow = convList.descendants(matching: .cell).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        // ChatView 出现。vertical TextField 在 XCTest 里可能是 TextView，所以用 any descendants。
        let input = app.descendants(matching: .any)["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()

        let msg = "smoke-\(Int(Date().timeIntervalSince1970))"
        input.typeText(msg)
        app.buttons["chatSend"].tap()

        // 回到会话列表，验证预览更新
        app.navigationBars.buttons.firstMatch.tap()

        let predicate = NSPredicate(format: "label CONTAINS[c] %@", msg)
        let previewCell = convList.staticTexts.containing(predicate).firstMatch
        XCTAssertTrue(previewCell.waitForExistence(timeout: 10), "expected conversation preview to show the message just sent")
    }
}
```

- [ ] **Step 3：跑 smoke**

后端需在跑；数据库需有至少 smoke@test.local 与另一账号之间的 conversation：

```bash
$UITEST
```

预期：`LoginSmokeTests` + `TabNavigationSmokeTests` + `ChatSmokeTests` 三套全绿。

**如果 `firstRow.tap()` 因为 List 的 cell identifier 不稳定找不到**：fallback 查找方式是通过 peer 名字的 staticText。本 smoke 最易碎的是"List 会话一定存在"的前提；CI 环境要专门准备这条 seed 数据。

- [ ] **Step 4：更新 README**

编辑 `ios-app/README.md` 的 `## Status` 块：

```markdown
## Status
- P1 done: scaffold + login/register/home.
- P2 done: main TabView (Chats / Contacts / Me), friends list, friend requests, user search, conversation list with unread badges, avatar caching via Nuke.
- P3 done: text messaging + real-time WebSocket (ChatView, optimistic send with clientTempId merge, retry on failure, older pagination, mark-as-read, reconnect + heartbeat, ChatsList live updates).
- P4-P8 tracked in `docs/superpowers/specs/2026-04-17-ios-app-design.md` §8.
```

- [ ] **Step 5：全量跑一轮**

```bash
$BUILD
$TEST
$UITEST
```

三项全绿。

- [ ] **Step 6：最终提交**

```bash
git add ios-app/EchoIMUITests/ChatSmokeTests.swift \
        ios-app/EchoIM/Features/Chat/ChatView.swift \
        ios-app/README.md
git commit -m "test(ios): add chat send smoke and note P3 completion"
```

---

## 模拟器联调清单（P3 全流程验收，跑完 14 项 task 之后必做）

后端 + 两个账号 A、B 互为好友。真机或模拟器各开一个登录 A、一个登录 B（或用 Web 客户端扮演 B）。

### 文字消息基本路径

- [ ] A 在会话列表点进与 B 的会话 → 看到过往消息（按时间序，旧到新）
- [ ] A 输入一条文字 + 发送 → 本地立即出现气泡（半透明的"发送中…"）；服务端 201 后气泡变实；B 端在 1 秒内收到这条
- [ ] B 回一条 → A 立即看到（LazyVStack 自动滚到底）
- [ ] 上滑到顶 → "加载更多"按钮 / 触发 loadOlder → 老消息 prepend 到顶端
- [ ] 点"加载更多"到服务端只回 < 50 条 → `hasMoreOlder = false`，按钮消失

### 断网与重连

- [ ] 在 ChatView 里断开 Mac Wi-Fi → 再发一条 → 气泡变"发送失败"，带"重试"按钮
- [ ] 恢复 Wi-Fi → NWPathMonitor 触发 connectIfNeeded → WS 重新 ready → 点"重试" → 气泡变 confirmed
- [ ] 切后台 10 秒 → 切回前台 → observe WebSocketClient state transitions：background 时 disconnect、active 时 connectIfNeeded → ready → ConversationsListViewModel 自动 refresh 会话列表
- [ ] App 被挂起期间 B 发了新消息 → A 回前台后很快看到 ConversationsListView 出现带 unread badge 的会话

### 已读游标

- [ ] A 进入会话 → PUT /read 发出（可在后端日志观察）；B 端（WEB）看不到已读回执（设计决定）
- [ ] A 多设备（模拟第二台设备）已读 → 第一台收到 `conversation.updated`，unread 清零；会话列表 badge 消失

### 草稿对话

- [ ] A 从"联系人"tab 点一个从未聊过的好友 C → ChatView 打开，输入框可用，消息列表为空
- [ ] A 发一条 → POST /api/messages → 服务端创建 conversation → 201 回包带 conversation_id → ChatViewModel.conversationId 回填 → 会话列表新增一行（`refresh()` 被 `applyIncomingMessage` 的"新会话"分支触发）
- [ ] 场景 2：A 停在 C 的草稿聊天页时 B 先给 A 发消息（实际上只可能是"C 先发"，这里换成 C）→ A 本端收到 `message.new` → `handleIncomingMessage` 草稿态分支命中 → conversationId 回填 → 消息出现

### 401 / 登出

- [ ] 手动把 Keychain token 改成无效（模拟 token 失效）→ 冷启动 → WS upgrade 401 → `handleUnauthorized` → `tearDownSession` → 回 LoginView
- [ ] 正常登出 → WS 断开 → wsClient = nil → 回 LoginView

---

## Self-Review（完成前必过）

- [ ] **P3 覆盖设计 §8**：逐项核对
  - `WebSocketClient`（§7）→ Task 4 + 5 + 6
  - `WSEvent` decode（§7.8 全集）→ Task 1
  - `MessageRepository` → Task 2 + Task 11（markRead）
  - `ChatView` + `ChatViewModel` → Task 8 + 9 + 10 + 11 + 12
  - 乐观发送 + `clientTempId` 合并 → Task 9 + 10（WS echo 合并）
  - 失败重试 → Task 9
  - 上滑分页 → Task 8
  - 进入会话标已读 → Task 11
  - `ChatsList` 接 WS 更新 → Task 13

- [ ] **明确延后到 P4+ 的项**（不做 = 成功）：
  - `?limit=` querystring → P4
  - SwiftData 缓存 / 连续后缀不变式 → P4
  - 图片消息相关 → P5
  - Presence / Typing 的 UI 响应（但 WS decode 不能崩）→ P6
  - `friend_request.*` 的增量处理 → P6+（P3 只解码）
  - UserSession 拆出 → P4
  - 前台恢复刷新 `currentUser` / 好友申请 / presence → P6（P3 只做 WS 连接的生命周期联动）

- [ ] **Placeholder 扫描**：
  `grep -rn -iE "tbd|todo|implement later|similar to task" docs/superpowers/plans/2026-04-21-ios-p3-messaging-websocket.md` 应为空（注：WebSocketClient.swift 里保留了 `TODO(P8): 接日志框架时记 warning` 是代码注释，不是计划 placeholder，可忽略）。

- [ ] **类型一致性**：
  - `Message`：id / conversationId / senderId / body / messageType / mediaUrl / createdAt / clientTempId
  - `MessageCursor`：.before(Int) / .after(Int)
  - `WSEvent`：messageNew / conversationUpdated / typingStart / typingStop / presenceOnline / presenceOffline / friendRequestNew / friendRequestAccepted / friendRequestDeclined / unknown(String)；**不**含 connection.ready（internal 消化）
  - `WSState`：disconnected / connecting / handshaking / ready / reconnecting(in:)
  - `MessageSendState`：confirmed / pending / failed(String)
  - `ChatRoute`：conversation(Conversation) / peer(UserProfile)
  - `ChatPhase`：idle / loading / loaded / error(String)
  - `LocalMessage.id` 用 `localId: String`（pending = clientTempId；confirmed = "id-{id}"）；**不**用 `Message.id: Int` 做 SwiftUI 身份——否则 optimistic 占位 id 会与真实 id 冲突

- [ ] **WS 生命周期钩子齐全**：
  - `handleLoginSuccess(_:)` → `ensureWSClient()`
  - `bootstrap()` 且有 token → `ensureWSClient()`
  - `logout()` → `tearDownSession()`
  - `handleUnauthorized()` → `tearDownSession()`
  - RootView `scenePhase.active` → `wsClient.connectIfNeeded()`
  - RootView `scenePhase.background` → `wsClient.disconnect(.userInitiated)`
  - WebSocketClient 401 → `onUnauthorized()` → `AppContainer.handleUnauthorized()`
  - WebSocketClient `didCloseWith` / `didCompleteWithError`（非 401）→ `scheduleReconnect()`
  - NWPathMonitor.satisfied（在 `.reconnecting` 且 `shouldReconnect == true` 时）→ `openSocket()` 抢跑

- [ ] **订阅生命周期**：
  - `ChatView.task` 调 `vm.attachWSSubscription()` 并在 `.onDisappear` 调 `detachWSSubscription()`
  - `ConversationsListView.task` 调 `attachWSSubscription()`；`.onDisappear` 对称 detach
  - `WSSubscription.cancel()` 清理 `handlers` 和 `readyHandlers` 两个字典（Task 13 Step 3）

- [ ] **乐观发送一致性**：
  - `sendText` 生成 `tempId`，插入 `.pending` 气泡
  - 201 REST 回包 → `mergeServerResult(result, tempId:)` → `.pending` → `.confirmed` + localId 切为 "id-{id}"
  - WS `message.new` 的 `client_temp_id` 也走同一个 `mergeServerResult`，REST 和 WS 谁先到都稳
  - 失败 → `.failed(String)`，保留 tempId；`retry(localId:)` 复用同一 tempId 重发（不换 id 保持幂等语义）
  - 草稿态：`conversationId == nil` → 201 回包后从 `message.conversationId` 回填
  - WS 草稿 promote：`handleIncomingMessage` 草稿态 + `sender_id == peer.id` → 回填 + append

- [ ] **测试覆盖**：
  - `MessageDecodingTests` 3 / `WSEventDecodingTests` 9 / `ReconnectPolicyTests` 3
  - `MessageRepositoryTests` 5（list 3 + sendText 1 + markRead 1）
  - `ChatViewModelLoadTests` 5 / `ChatViewModelSendTests` 5 / `ChatViewModelWSTests` 6 / `ChatViewModelReadTests` 4
  - `ChatSmokeTests` 1（UI smoke）
  - 与 P2 测试无回归

- [ ] **已知妥协显式记录**：重试可能造成服务端重复行——在文件顶部"已知妥协"段已写入，不是隐藏 bug

- [ ] **工作目录一致**：所有路径都以 `ios-app/EchoIM/...` 开头，无裸相对路径

---

## 未来阶段的依赖锚点（给 P4+ 计划起草人）

**P4 会触及本阶段的文件**：
- `ChatViewModel` 重写 `load()` / `loadOlder()` / `refetchMissedMessages()`：引入 `MessageStore` / `ConversationMetaStore`（`@ModelActor`），遵循设计 §5.2 的连续后缀不变式；本地先渲染，远端补齐。
- `AppContainer` 拆出 `UserSession`（设计 §2.2），`wsClient` / `makeXxxRepository()` 迁入 `UserSession`；`tearDownSession` 扩展为三阶段（Nuke → session=nil → 删 SwiftData 目录）。
- `ConversationsListViewModel` 先读 `ConversationMetaStore.loadAll()` 立即渲染，再异步 refresh。

**P5 会触及本阶段的文件**：
- `ChatViewModel.sendText` 复用 → 新增 `sendImage`；`LocalMessage.localImageData` 终于派上用场；`ImageMessageBubble` + `LazyImage` 远程图片；`ImageSendStage` 阶段化重试。
- `MessageRepository` 已不变（sendText 不动）；新增 `UploadRepository.uploadMessageImage`。

**P6 会触及本阶段的文件**：
- `ChatViewModel.handleWSEvent` 的 `default:` 分支打开 typing 事件处理；新增 typing debounce 发送 → `WebSocketClient.send(_ clientEvent:)` 预留的 API。
- `ConversationsListViewModel` 订阅 `friend_request.*` 以替代 ContactsView 的 `.refreshable`（或由 ContactsViewModel 订阅并做增量 merge）。
- Presence：新增 `PresenceStore`（设计 §4 目录 `Shared/Stores/`），AvatarView 接入在线圆点。

**P3 引入的设计债**：
- `WebSocketClient` 没有单元测试层；P8 "打磨 + 测试"可考虑抽 `URLSessionWebSocketTaskProtocol`，给状态机写一组 mock 驱动的测试。
- `ChatViewModel.refetchMissedMessages()` 是 P3 的简化版（一次 after-cursor 就返回），P4 替换成循环翻页 + 安全阀（设计 §5.3 场景 C）。
