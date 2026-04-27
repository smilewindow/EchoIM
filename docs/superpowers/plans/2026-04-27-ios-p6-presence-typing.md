# iOS P6 实施计划：Presence + Typing

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ios-app/` 从 P5 的"图片消息 + 阶段化重试"推进到"好友在线状态 + 输入指示完整对齐 Web 端"——对应设计文档第 8 节的 P6 阶段（§7.5 step 5 + §7.8 + §2.1 中 `Features/Shared/Stores/`）。具体落地：
- 好友列表 / 会话列表 / 聊天页顶部显示对方在线圆点（绿点跟随 `presence.online` / `presence.offline`）
- 聊天页顶部显示"正在输入..."（5 秒安全定时器；服务端 stop 丢失也会自动消失）
- 输入框打字时本端 debounce 发 `typing.start`，3 秒空闲或发送/离开页面立即发 `typing.stop`
- 重连后 `connection.ready` 触发 `PresenceStore.clearAll()`，被动接收服务端循环 push 的多条 `presence.online` 重建集合（设计 §7.5 step 5）

**Architecture:** 三件事并行展开：

1. **iOS 状态层（共享 Store）**：新增 `Features/Shared/Stores/PresenceStore.swift`（`@Observable @MainActor`，`Set<Int>` 形式存储在线好友 id）和 `Features/Shared/Stores/TypingStore.swift`（`@Observable @MainActor`，`Set<Int>` 形式存储正在输入的 conversation_id，附 5 秒安全 Task 自动清理）。两者都不与 WebSocketClient 直接耦合——由 `UserSession` 担任"路由器"，在 init 时给 wsClient 注册一组转发订阅，把 `presence.online/.offline` / `typing.start/.stop` / `connection.ready` 信号灌进对应 store。这样 ChatViewModel / FriendsListView 只读 store，不重复订阅同类事件。

2. **iOS 网络层**：`WebSocketClient` 增加一个 `sendTyping(conversationId:isStart:)` 方法——`URLSessionWebSocketTask.send(.string(...))` 写入 `{type:"typing.start"|"typing.stop", conversation_id:N}`。仅在 `.ready` 状态下发送；其他状态静默丢弃（与 Web 端 `sendWsMessage` 的行为一致——握手未完时打字不发，恢复后才有意义）。

3. **iOS UI 层**：新增 `Core/UI/PresenceDot.swift`（默认 10pt 绿色圆点 + 1.5pt 白边——好友列表 / 会话列表用默认尺寸；聊天页 header 用 `PresenceDot(size: 8)` 更紧凑）；`AvatarView` 加可选的 `showsPresence` 重载或在外层包一层 ZStack 加 `PresenceDot`。`FriendsListView` / `ConversationsListView`（`ConversationRow`）/ `ChatView`（自定义 `.toolbar(.principal)`）在三个位置渲染圆点。`ChatView` 顶部 principal 区改成"昵称 + 圆点 + 子标题（typing 时显示'正在输入...'）"的两行布局。输入框 `TextField` 的 `onChange(of: draft)` 触发 `vm.handleTypingInput()`；`vm.sendText` / `onDisappear` 调 `vm.stopTyping()`。

**Tech Stack:** SwiftUI（`.toolbar(.principal)` 自定义导航中央视图）、Swift Concurrency（`Task` 起 5 秒延迟兜底定时器、`Task` 起 3 秒发送方 idle 定时器）、`URLSessionWebSocketTask.send(.string)`、`@Observable` 宏（让所有视图自动跟随 store 更新）、Swift Testing、XCUITest。

**TDD 适用范围（与 P1/P2/P3/P4/P5 一致）：**

- **纯逻辑 → TDD**：
  - `PresenceStore` 的 `setOnline` / `setOffline` / `clearAll` / `isOnline` 四组小用例。
  - `TypingStore.handleTypingStart` 写入 + `handleTypingStop` 提前清理 + 5 秒后兜底自动清理（用注入的 `safetyDuration: 0.05` 跑出真实 elapsed）。
  - `UserSession` 事件路由（presence/typing/onReady → store）由 `UserSessionRoutingTests` 覆盖；`ChatViewModel.handleWSEvent` 对 `.presenceOnline` / `.presenceOffline` / `.typingStart` / `.typingStop` **保持 no-op**——单测 `handleWSEventIgnoresTypingForOtherConversation` 锁住 VM 不重复路由（不变式 8）。
  - `ChatViewModel.handleTypingInput` 第一次调用发 `typing.start`、3 秒静默后发 `typing.stop`、连续按键不重复发 start、`stopTyping` 立即发 stop（用注入的 `idleDuration: 0.05` 验证；用 `recordingTypingSender` 收发）。
  - `WebSocketClient.sendTyping` 把 payload 编成正确 JSON、`.ready` 之外不发送（用 `URLSessionWebSocketTask` 的真实 task 不太好测；改为在 `WebSocketClient` 里抽一层 `typingFrameJSON(...)` 纯函数，对它做单测；调度路径用 state guard 编译期保护）。
- **View / Toolbar / Picker → 编译 + XCUITest smoke + 模拟器手工**：`PresenceDot` 圆点尺寸 / 颜色（手工 + 截屏比对）；`ChatView` toolbar.principal 自定义视图（XCUITest 断言 accessibility identifier 在场）。

**服务端契约改动：** 无。`presence.online` / `presence.offline` / `typing.start` / `typing.stop` 全部在服务端 P6 已实现（`server/src/plugins/ws.ts:123-157`、`server/src/plugins/ws.ts:253-277`，相应 `server/tests/ws.test.ts` 已覆盖）。**P6 不开 server task**——本计划里出现的所有命令都不应改 `server/` 任何文件。

**不在 P6 范围（明确延后）：**
- **多设备/多会话场景下的 typing 聚合 UI**：当前只渲染当前打开的 ChatView 顶部"正在输入..."。会话列表里"小气泡 / 三点动画"延后到 P8（与 Web 端一致——Web 也只在 ChatView 显示）。
- **群聊场景**：服务端 typing payload 已有 `user_id`，但 1-on-1 业务下我们只用 `conversation_id` 维度，TypingStore 不按用户存。改群聊时再扩 `Set<Int>` → `[ConversationId: Set<UserId>]`。
- **后台维持 presence**：iOS 进 `.background` 我们主动 disconnect WS（设计 §7.1），所以好友看到我离线、我看不到任何 presence 变化都符合预期。`scenePhase` 已在 P3 处理好，P6 不动。
- **状态文本（"在线 / 上次活跃于 5 分钟前"）**：Web 端也只显示绿点；P6 对齐就好。
- **键盘上浮 / 输入栏跟随**：P8 主题。
- **Profile / 头像变更**：P7 主题；本阶段 `AvatarView` API 不动，只在外层覆盖 `PresenceDot`。

**已知妥协：**
- **`PresenceStore.clearAll()` 由 `UserSession` 在 `onReady` 时统一触发，而不是 ChatViewModel 自己**。理由：clear-then-rebuild 是连接级事件（每次重连都要做），重复在多个 VM 里订阅会引入"谁先收到 ready 谁先 clear"的竞态；统一在 UserSession 这一处订阅、写入 PresenceStore，既保证幂等也只跑一次。
- **`TypingStore` 用 `@MainActor` Swift Task 做 5 秒兜底**：相比 web 用 `setTimeout` 的简单计数，Task 取消语义更稳；但代价是单测需要 await 真实时间流逝。我们注入小常数（`safetyDuration: 0.05`）跑过真实定时器，不引入 mock clock。
- **`ChatViewModel.handleTypingInput` 的 3 秒 idle 定时器同样用 Task**：和 TypingStore 同一份套路。
- **PhotosPicker 选完图后切走聊天页**：P5 已知问题——`onChange(of: pickedItem)` Task 还在跑。P6 不解决。
- **`WebSocketClient.sendTyping` 在 `.ready` 之外静默丢弃**：与 Web `sendWsMessage` 行为一致；用户在 `.handshaking` / `.reconnecting` 状态打字不会触发 typing 事件，但本端 UI 已经能输入文本，体验上无感（typing 指示对发送方也无效，他在等连上）。
- **`PresenceDot` 不监听 PresenceStore 的"未知好友"——只在持有 friend.id 的位置渲染**：`PresenceStore.onlineUserIds` 可能包含我从未在本地建过 row 的用户（边界场景），渲染层不主动加新 row。
- **`ChatView` toolbar.principal 自定义视图的 accessibility 命名**：iOS 17 SwiftUI `principal` 自带 NavigationBar 的 accessibilityElement 收敛规则，给子节点单独打 ID 在 XCUITest 中需要 `.accessibilityElement(children: .contain)` 显式声明。Task 9 / Task 10 中处理。

**重要不变式（实现前必须读懂，实现中容易踩到）：**

1. **`PresenceStore` 不订阅 WS，由 `UserSession` 路由**：禁止在 PresenceStore 里持有 wsClient 或 subscription。Store 是纯状态容器；事件路由在 UserSession（与 Web `client/src/hooks/useWebSocket.ts:62-86` 的"在 hook 里 dispatch 给 store"思路一致）。这条不变式让单测无需 wsClient 即可全量覆盖 store。
2. **`presence.online` 在重连后会被服务端循环推送多条**：服务端 `ws.ts:sendPresenceSnapshot` 对每个在线好友单独 send 一帧；客户端不能假设只来一条。`PresenceStore.setOnline` 用 `Set.insert` 天然幂等。**没有** `presence.snapshot` 这个事件，不要去监听它（设计 §7.5 step 5 已强调）。
3. **`clearAll` 必须在第一条 `presence.online` 到达之前执行**：服务端发 `connection.ready` 后立刻顺序 send 多条 `presence.online`。我们在 WebSocketClient `handleReceivedMessage` 处理 `connection.ready` 时同步调用 `readyHandlers`，readyHandlers 跑完才会进下一轮 receive。所以 UserSession 的 `onReady → presenceStore.clearAll()` 在事件循环顺序上严格早于后续 `.presenceOnline` 派发，安全。
4. **`typing.stop` 必须在三种触发点都发**：① 输入 idle 3 秒；② 用户发送消息（按发送按钮）；③ 用户离开 ChatView（`onDisappear`）。漏掉任意一种都会让对方"卡在正在输入"——直到他们的 5 秒安全定时器兜底。这是 §7.8 表里 client 端 typing 的完整契约，对齐 Web `client/src/components/ChatView.tsx:282-293`。
5. **`typing.start` 必须 dedupe**：连续按键不能每次都发 start——会刷服务端日志，且大概率被 socket 限速。用本端 `typingSendActive: Bool` 标志避免重复发。第一次发 start → 设 true → idle 计时；3 秒 idle 触发 stop → 设 false。下一次按键又从 false 起步。对齐 Web 端 `typingActiveRef`。
6. **`TypingStore` 的安全定时器必须可重置**：每次 `handleTypingStart` 都要 cancel 旧定时器再起新的——否则连续两次 start 之间，旧定时器先到期会把"还在输入"的状态错误清空。Web 端用 `clearTimeout` 处理，我们用 `Task.cancel`。
7. **`TypingStore` 5 秒 > 发送方 3 秒 idle**：服务端不主动补 stop（除非客户端发了），所以接收方安全定时器必须严格大于发送方 idle，留 1-2 秒"start/stop 路上"buffer。设计 §8 P6 已指定 5 秒。
8. **VM 不重复路由 typing/presence**：`UserSession` 是 `presenceStore` / `typingStore` 的**唯一**写入方（不变式 1 的推论）。`ChatViewModel.handleWSEvent` 的 `default: return` 分支**保持不变**——既不在 VM 里调 `typingStore.handleTypingStart` 也不调 `presenceStore.setOnline`，否则会导致同一事件被写两次。VM 只**读** `typingStore.isTyping(...)`（通过 `peerIsTyping` 计算属性，见 Task 5），presence 同理由 ChatView 读 `presenceStore.isOnline(...)` 渲染圆点。这条不变式由 Task 5 测试 `handleWSEventIgnoresTypingForOtherConversation` 锁住。

---

## 开发环境前提

沿用 P1/P2/P3/P4/P5。命令约定：

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

> 如本机没有 `OS=latest` 的 iPhone 15 目标，按 P5 经验改 `-destination 'platform=iOS Simulator,OS=17.5,name=iPhone 15'`。

服务端不动，但仍需保证现有 ws / messages 测试通过：

```bash
npm test --prefix server -- ws messages
```

工作目录约定：所有 iOS 路径以 `ios-app/EchoIM/` 开头；下方 Step 里 `$BUILD` / `$TEST` / `$UITEST` 占位等价于上面三条 `xcodebuild` 命令。

---

## 文件结构

新增文件：

```
ios-app/EchoIM/
├── Core/
│   └── UI/
│       └── PresenceDot.swift                  // 新：默认 10pt 绿点 + 1.5pt 白边（聊天页 header 显式传 size: 8）
└── Features/
    └── Shared/
        └── Stores/
            ├── PresenceStore.swift            // 新：@Observable @MainActor
            └── TypingStore.swift              // 新：@Observable @MainActor + 5s 安全 Task
ios-app/EchoIMTests/
├── PresenceStoreTests.swift                   // 新
├── TypingStoreTests.swift                     // 新
├── ChatViewModelTypingTests.swift             // 新（输入 debounce + sendTyping 路由）
├── ChatViewModelPresenceTests.swift           // 新（事件派发 + clearAll on ready）
├── UserSessionRoutingTests.swift              // 新（presence/typing/onReady 转发到 store）
└── WebSocketClientTypingFrameTests.swift      // 新（typingFrameJSON 纯函数测试）
ios-app/EchoIMUITests/
└── PresenceTypingSmokeTests.swift             // 新
```

修改文件：

```
ios-app/EchoIM/
├── App/
│   ├── AppContainer.swift                     // 不动
│   └── UserSession.swift                      // +presenceStore / typingStore / 转发订阅 / +typingSender 封装
├── Core/
│   └── Networking/
│       └── WebSocketClient.swift              // +sendTyping(conversationId:isStart:) + typingFrameJSON 纯函数
├── Core/
│   └── UI/
│       └── AvatarView.swift                   // 不动（圆点叠加在调用方 ZStack 里做，避免 API 膨胀）
├── Features/
│   ├── Chat/
│   │   ├── ChatView.swift                     // +toolbar(.principal) + typing 文案 + draft.onChange + onSend stop + onDisappear stop
│   │   └── ChatViewModel.swift                // +handleTypingInput / +stopTyping / +typingSender / +typingStore / +peerIsTyping 计算属性（handleWSEvent 不动；typing/presence no-op，路由由 UserSession 负责）
│   ├── Conversations/
│   │   └── ConversationsListView.swift        // ConversationRow 加 PresenceDot
│   ├── Contacts/
│   │   ├── ContactsView.swift                 // 把 presenceStore 透传给 FriendsListView
│   │   └── FriendsListView.swift              // 行内加 PresenceDot
│   └── Main/
│       └── MainTabView.swift                  // 把 presenceStore / typingStore / typingSender 透传给两个 tab
└── ...
```

每个文件单一职责。`PresenceStore` 与 `TypingStore` 拆开是因为生命周期不同（presence 跨整个 session 都活；typing 是按会话的、可被快速 reset）。`PresenceDot` 单独成文件以便 P7 头像编辑界面、未来"附近的人"等也能直接复用。

---

## Task 1: PresenceStore — `@Observable` 在线好友集合 ✅

**Files:**
- Create: `ios-app/EchoIM/Features/Shared/Stores/PresenceStore.swift`
- Test: `ios-app/EchoIMTests/PresenceStoreTests.swift`

设计依据：§2.1（`Features/Shared/Stores/PresenceStore.swift`）+ §7.5 step 5。store 是纯状态容器，不与 WebSocketClient 耦合（不变式 1）。

> **实现说明**：项目使用 `PBXFileSystemSynchronizedRootGroup`（Xcode 16+），新建 Swift 文件无需手动修改 `project.pbxproj`，文件系统变更自动被 Xcode 识别。新增 `ios-app/EchoIM/Features/Shared/Stores/` 目录即可。

- [x] **Step 1: 写测试 — set / unset / isOnline / clearAll 四组基础语义**

```swift
// ios-app/EchoIMTests/PresenceStoreTests.swift
import Testing
@testable import EchoIM

@MainActor
@Suite
struct PresenceStoreTests {
    @Test
    func setOnlineAddsUserId() {
        let store = PresenceStore()
        store.setOnline(42)
        #expect(store.isOnline(42))
        #expect(store.onlineUserIds == [42])
    }

    @Test
    func setOnlineIsIdempotent() {
        let store = PresenceStore()
        store.setOnline(42)
        store.setOnline(42)
        #expect(store.onlineUserIds.count == 1)
    }

    @Test
    func setOfflineRemovesUserId() {
        let store = PresenceStore()
        store.setOnline(42)
        store.setOffline(42)
        #expect(!store.isOnline(42))
        #expect(store.onlineUserIds.isEmpty)
    }

    @Test
    func setOfflineForUnknownUserIsNoOp() {
        let store = PresenceStore()
        store.setOffline(42)        // 之前没 setOnline 过
        #expect(store.onlineUserIds.isEmpty)
    }

    @Test
    func clearAllEmptiesSet() {
        let store = PresenceStore()
        store.setOnline(1)
        store.setOnline(2)
        store.setOnline(3)
        store.clearAll()
        #expect(store.onlineUserIds.isEmpty)
        #expect(!store.isOnline(1))
    }
}
```

- [x] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/PresenceStoreTests`
Expected: 编译失败（`PresenceStore` 未定义）。

- [x] **Step 3: 实现 PresenceStore**

```swift
// ios-app/EchoIM/Features/Shared/Stores/PresenceStore.swift
import Foundation
import Observation

/// 设计 §2.1。在线好友 id 的 @Observable 容器。
/// 不订阅 WebSocketClient——事件路由由 UserSession 完成（不变式 1）。
@Observable
@MainActor
final class PresenceStore {
    private(set) var onlineUserIds: Set<Int> = []

    func setOnline(_ userId: Int) {
        onlineUserIds.insert(userId)
    }

    func setOffline(_ userId: Int) {
        onlineUserIds.remove(userId)
    }

    func isOnline(_ userId: Int) -> Bool {
        onlineUserIds.contains(userId)
    }

    /// 设计 §7.5 step 5：重连收到 connection.ready 后调用，由 UserSession 触发。
    /// 服务端会在 connection.ready 之后顺序 send 当前在线好友的 presence.online，
    /// 我们靠后续事件重建集合。
    func clearAll() {
        onlineUserIds.removeAll()
    }
}
```

- [x] **Step 4: 跑测试，确认通过**

Run: `$TEST -only-testing:EchoIMTests/PresenceStoreTests`
Expected: 5 条全过。✅ 实际结果：5 条全过。

- [x] **Step 5: 提交**

```bash
git add ios-app/EchoIM/Features/Shared/Stores/PresenceStore.swift \
         ios-app/EchoIMTests/PresenceStoreTests.swift
git commit -m "feat(ios): add PresenceStore observable set"
```

---

## Task 2: TypingStore — `@Observable` 正在输入会话集合 + 5 秒安全定时器 ✅

**Files:**
- Create: `ios-app/EchoIM/Features/Shared/Stores/TypingStore.swift`
- Test: `ios-app/EchoIMTests/TypingStoreTests.swift`

设计依据：§8 P6 "TypingStore 带 5 秒安全定时器"。store 持有 `Set<Int>` 形式的 `typingConversationIds`；每次 `handleTypingStart(conversationId:)` 都重置一个 5 秒后自动 `handleTypingStop` 的 `Task`，保证服务端 stop 丢失时也能复位（不变式 6）。`safetyDuration` 通过 init 注入，单测用 0.05 秒。

- [x] **Step 1: 写测试 — start 写入 + 提前 stop 清理 + 兜底自动清理**

```swift
// ios-app/EchoIMTests/TypingStoreTests.swift
import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite
struct TypingStoreTests {
    @Test
    func startInsertsConversationId() {
        let store = TypingStore(safetyDuration: 5.0)
        store.handleTypingStart(conversationId: 7)
        #expect(store.isTyping(7))
        #expect(store.typingConversationIds == [7])
    }

    @Test
    func explicitStopClearsImmediately() {
        let store = TypingStore(safetyDuration: 5.0)
        store.handleTypingStart(conversationId: 7)
        store.handleTypingStop(conversationId: 7)
        #expect(!store.isTyping(7))
    }

    @Test
    func startIsIdempotentWithinWindow() async {
        let store = TypingStore(safetyDuration: 5.0)
        store.handleTypingStart(conversationId: 7)
        store.handleTypingStart(conversationId: 7)
        #expect(store.typingConversationIds.count == 1)
    }

    @Test
    func safetyTimerAutoStops() async throws {
        let store = TypingStore(safetyDuration: 0.05)
        store.handleTypingStart(conversationId: 7)
        #expect(store.isTyping(7))

        // 等 0.2s（远大于 0.05s 兜底），状态应被自动清空
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!store.isTyping(7))
    }

    @Test
    func consecutiveStartsResetSafetyTimer() async throws {
        let store = TypingStore(safetyDuration: 0.10)
        store.handleTypingStart(conversationId: 7)
        try await Task.sleep(nanoseconds: 60_000_000)   // 0.06s
        // 旧定时器还没到期就再来一次 start——必须 reset 成新的 0.10s
        store.handleTypingStart(conversationId: 7)
        try await Task.sleep(nanoseconds: 60_000_000)   // 又过 0.06s（共 0.12s，但新定时器才走了 0.06s）
        #expect(store.isTyping(7), "second start should have reset the safety timer")

        try await Task.sleep(nanoseconds: 100_000_000)  // 再等 0.10s 让新定时器到期
        #expect(!store.isTyping(7))
    }

    @Test
    func explicitStopCancelsSafetyTimer() async throws {
        let store = TypingStore(safetyDuration: 0.05)
        store.handleTypingStart(conversationId: 7)
        store.handleTypingStop(conversationId: 7)
        try await Task.sleep(nanoseconds: 100_000_000)
        // explicit stop 之后再到期的定时器不应该错把别的状态清掉——这里 7 早就 stop，确认依然为空且无副作用。
        #expect(store.typingConversationIds.isEmpty)
    }

    @Test
    func independentConversationsAreTrackedSeparately() {
        let store = TypingStore(safetyDuration: 5.0)
        store.handleTypingStart(conversationId: 7)
        store.handleTypingStart(conversationId: 8)
        store.handleTypingStop(conversationId: 7)
        #expect(!store.isTyping(7))
        #expect(store.isTyping(8))
    }
}
```

- [x] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/TypingStoreTests`
Expected: 编译失败（`TypingStore` 未定义）。

- [x] **Step 3: 实现 TypingStore**

```swift
// ios-app/EchoIM/Features/Shared/Stores/TypingStore.swift
import Foundation
import Observation

/// 设计 §8 P6。`@Observable` 会话级输入指示集合。
/// 每个 conversationId 维护独立的 5 秒兜底 Task，保证服务端 stop 丢失也能复位（不变式 6 / 7）。
@Observable
@MainActor
final class TypingStore {
    private(set) var typingConversationIds: Set<Int> = []

    private var safetyTimers: [Int: Task<Void, Never>] = [:]
    private let safetyDuration: TimeInterval

    init(safetyDuration: TimeInterval = 5.0) {
        self.safetyDuration = safetyDuration
    }

    /// 处理服务端转发的 typing.start。重置该会话的兜底定时器。
    func handleTypingStart(conversationId: Int) {
        typingConversationIds.insert(conversationId)
        safetyTimers[conversationId]?.cancel()

        let nanos = UInt64(safetyDuration * 1_000_000_000)
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self else { return }
            self.handleTypingStop(conversationId: conversationId)
        }
        safetyTimers[conversationId] = task
    }

    /// 处理服务端转发的 typing.stop（或兜底定时器自动调用）。同步取消该会话兜底定时器。
    func handleTypingStop(conversationId: Int) {
        typingConversationIds.remove(conversationId)
        safetyTimers.removeValue(forKey: conversationId)?.cancel()
    }

    func isTyping(_ conversationId: Int) -> Bool {
        typingConversationIds.contains(conversationId)
    }
}
```

- [x] **Step 4: 跑测试，确认通过**

Run: `$TEST -only-testing:EchoIMTests/TypingStoreTests`
Expected: 7 条全过。✅ 实际结果：7 条全过（含定时器 async 测试）。

- [x] **Step 5: 提交**

```bash
git add ios-app/EchoIM/Features/Shared/Stores/TypingStore.swift \
         ios-app/EchoIMTests/TypingStoreTests.swift
git commit -m "feat(ios): add TypingStore with safety timer"
```

---

## Task 3: WebSocketClient.sendTyping — 客户端唯一一种主动 WS 帧 ✅

**Files:**
- Modify: `ios-app/EchoIM/Core/Networking/WebSocketClient.swift`
- Test: `ios-app/EchoIMTests/WebSocketClientTypingFrameTests.swift`

设计依据：§7.8 表 "客户端发的 WS 事件（仅这两种）"。服务端 `ws.ts:253-277` 期望 `{type:'typing.start'|'typing.stop', conversation_id:N}` 这种平铺 JSON（**不是** `{type, payload:{conversation_id}}` 那种嵌套）。`URLSessionWebSocketTask.send` 的真实 task 不好测，所以把序列化抽出来做一层纯函数 `Self.typingFrameJSON(...) -> Data` 单测，发送路径用编译期 state guard 保护。

> **实现说明**：Task 4 所需的 `_dispatchForTesting` / `_fireReadyForTesting` DEBUG 测试入口也随本 Task 一并加入 WebSocketClient，放在同一文件的 `#if DEBUG extension`，与计划 Task 4 Step 2 保持同步，避免 Task 4 编译失败。

- [x] **Step 1: 写测试 — typingFrameJSON 输出形状**

```swift
// ios-app/EchoIMTests/WebSocketClientTypingFrameTests.swift
import Foundation
import Testing
@testable import EchoIM

@Suite
struct WebSocketClientTypingFrameTests {
    @Test
    func typingStartFrameHasFlatShape() throws {
        let data = try WebSocketClient.typingFrameJSON(
            conversationId: 42,
            isStart: true
        )
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["type"] as? String == "typing.start")
        #expect(json["conversation_id"] as? Int == 42)
        // 服务端解析时只读 type / conversation_id；不要嵌套 payload
        #expect(json["payload"] == nil)
    }

    @Test
    func typingStopFrameHasFlatShape() throws {
        let data = try WebSocketClient.typingFrameJSON(
            conversationId: 7,
            isStart: false
        )
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["type"] as? String == "typing.stop")
        #expect(json["conversation_id"] as? Int == 7)
    }
}
```

- [x] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/WebSocketClientTypingFrameTests`
Expected: 编译失败（`WebSocketClient.typingFrameJSON` 不存在）。

- [x] **Step 3: 在 WebSocketClient 加 typingFrameJSON 静态函数 + sendTyping 方法**

在 `ios-app/EchoIM/Core/Networking/WebSocketClient.swift` 末尾追加：

```swift
extension WebSocketClient {
    /// 客户端唯一会主动发的两类帧：typing.start / typing.stop。设计 §7.8。
    /// 服务端 `server/src/plugins/ws.ts:253-277` 期望平铺 JSON，**不**嵌套 payload。
    ///
    /// **`nonisolated`**：WebSocketClient 整体是 `@MainActor`，但本函数不读写 actor 状态，
    /// 显式 nonisolated 让任何 actor 上下文（包括无 `@MainActor` 的测试）都能直接调用，
    /// 避免后续 Test suite 出现 "actor isolation" 编译错误。
    nonisolated static func typingFrameJSON(conversationId: Int, isStart: Bool) throws -> Data {
        let payload: [String: Any] = [
            "type": isStart ? "typing.start" : "typing.stop",
            "conversation_id": conversationId,
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    /// 仅 .ready 状态下发送；其它状态静默丢弃（与 Web `sendWsMessage` 一致）。
    /// 序列化失败极少发生，发送错误也仅记录到 log（P8 接日志体系）；
    /// 调用方只关心"start/stop 已尽力发出"，不需要等待结果。
    func sendTyping(conversationId: Int, isStart: Bool) {
        guard case .ready = state, let task else { return }
        guard let data = try? Self.typingFrameJSON(
            conversationId: conversationId,
            isStart: isStart
        ),
        let text = String(data: data, encoding: .utf8) else { return }

        task.send(.string(text)) { _ in
            // 失败仅作为可观察现象——下一次 idle 还会有机会发 stop；
            // 现阶段不做重试，避免拥塞。
        }
    }
}
```

- [x] **Step 4: 跑测试，确认通过**

Run: `$TEST -only-testing:EchoIMTests/WebSocketClientTypingFrameTests`
Expected: 2 条全过。✅ 实际：2 条全过。ReconnectPolicyTests 也无回归。

同时跑全部 WebSocket 相关测试避免回归：

Run: `$TEST -only-testing:EchoIMTests/ReconnectPolicyTests`
Expected: 不变。✅

- [x] **Step 5: 提交**

```bash
git add ios-app/EchoIM/Core/Networking/WebSocketClient.swift \
         ios-app/EchoIMTests/WebSocketClientTypingFrameTests.swift
git commit -m "feat(ios): add WebSocketClient.sendTyping for client typing frames"
```

---

## Task 4: UserSession 路由订阅 — presence/typing 事件灌进 store + onReady 清空 PresenceStore ✅

**Files:**
- Modify: `ios-app/EchoIM/App/UserSession.swift`
- Test: `ios-app/EchoIMTests/UserSessionRoutingTests.swift`

设计依据：§2.2 + §7.5 step 5 + 不变式 1（store 不订阅 WS，由 UserSession 路由）+ 不变式 3（clearAll 在 connection.ready 期间同步执行，先于 presence.online 派发）。

`UserSession` 持有 `let presenceStore = PresenceStore()` / `let typingStore = TypingStore()` 两个常量；在 init 末尾给 wsClient 注册三组订阅：
- `wsClient.onReady` → `presenceStore.clearAll()`
- `wsClient.subscribe` 中 `.presenceOnline` / `.presenceOffline` → presenceStore.setOnline/setOffline
- `wsClient.subscribe` 中 `.typingStart` / `.typingStop` → typingStore.handleTypingStart/Stop

订阅句柄保存到 `private var routingSubscriptions: [WSSubscription]` 数组里，随 UserSession / wsClient 整体释放自然失效——`WSSubscription.cancel()` 是幂等的、对已释放的 client 只是 no-op。**不加 deinit**：UserSession 是 `@MainActor` 类，cancel 也得在 MainActor 上跑，deinit 里强行 `Task { @MainActor in ... }` 反而引入异步释放窗口。如果未来发现订阅在 wsClient 还活着的时候需要单独解绑，再补显式 `tearDown()` 方法。

> **实际偏差**：TypingStoreTests 的定时器测试（`safetyTimerAutoStops` / `consecutiveStartsResetSafetyTimer` / `explicitStopCancelsSafetyTimer`）在全量并行运行时出现 flaky——0.05s / 0.06s / 0.10s 的 sleep 在模拟器高负载下精度不够。将参数统一上调：`safetyDuration` 改为 0.10 / 0.20，等待时间改为 0.30s / 0.50s，确保全量测试稳定通过。此调整已同步更新 `TypingStoreTests.swift`，一并在本 Task 提交。

- [x] **Step 1: 写测试 — 模拟 wsClient handler 注入事件，断言 store 状态**

> 实现思路：`WebSocketClient` 的 init 已支持注入 `tokenProvider` / `onUnauthorized`，但 subscribe 把订阅返回给上层、handlers 字典是 private。要测"UserSession 内部建立的订阅"最干净的方式是给 `WebSocketClient` 加一个 `#if DEBUG _dispatchForTesting(_:)` / `_fireReadyForTesting()` 内部入口（Step 2 实施），让测试直接派发事件、走 UserSession init 已经注册好的真实 routing handler——这与 P5 在 ChatViewModel 上 `_injectFailedImageBubbleForTesting` 的处理方式一致。
>
> 不引入 in-memory ModelContainer：`UserSession.init` 会按 userId 在 `applicationSupport/EchoIM/users/<userId>/` 落 SQLite。我们用 `Int.random(in: 900_000_000...)` 取唯一 userId、用 `withFixture` helper 显式 await cleanup（见下方实现）。这是与 `UserSessionTests` 一致的成熟模式。
>
> 不抽 `attachRoutingSubscriptions` helper：路由订阅就是 init 里的 3 行 `subscribe` / `onReady` 调用，没复杂逻辑值得单独提取；保留在 init 里更直观。

```swift
// ios-app/EchoIMTests/UserSessionRoutingTests.swift
import Foundation
import Testing
import SwiftData
@testable import EchoIM

@MainActor
@Suite
struct UserSessionRoutingTests {
    /// 与 UserSessionTests 同样的策略：每个测试用 900M+ 范围的随机 userId，
    /// 测试结束 removeItem 清掉 store 目录，避免污染真实 ApplicationSupport。
    private struct Fixture {
        let session: UserSession
        let storeDir: URL
    }

    private func makeFixture() throws -> Fixture {
        let userId = Int.random(in: 900_000_000...999_999_999)
        let storeDir = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)")
        let session = try UserSession(
            userId: userId,
            apiClient: APIClient(),
            tokenLoader: { nil },
            onUnauthorized: {}
        )
        return Fixture(session: session, storeDir: storeDir)
    }

    /// 显式 await 形式 of teardown：让 fixture 的 ModelContainer 引用先放掉，
    /// yield 一次让 SwiftData 关文件，再删目录——保证 cleanup 在测试 return 前完成。
    ///
    /// 关键：用 `var fixture: Fixture?` 而不是 `let`——`let` 会强持有 `fixture.session`
    /// 直到方法返回，删目录时 ModelContainer 还没释放，磁盘上的 .sqlite-wal/.shm 句柄仍开着。
    /// `fixture = nil` 让 UserSession 在 yield 前先被释放掉，再走文件系统删除。
    /// body 标 `@MainActor` 贴合内部访问 UserSession / stores 的隔离。
    private func withFixture<T>(
        _ body: @MainActor (Fixture) async throws -> T
    ) async throws -> T {
        var fixture: Fixture? = try makeFixture()
        let storeDir = fixture!.storeDir
        do {
            let result = try await body(fixture!)
            fixture = nil
            await Task.yield()
            try? FileManager.default.removeItem(at: storeDir)
            return result
        } catch {
            fixture = nil
            await Task.yield()
            try? FileManager.default.removeItem(at: storeDir)
            throw error
        }
    }

    @Test
    func presenceOnlineEventInsertsIntoPresenceStore() async throws {
        try await withFixture { fixture in
            fixture.session.wsClient._dispatchForTesting(
                .presenceOnline(UserIdPayload(userId: 7))
            )
            #expect(fixture.session.presenceStore.isOnline(7))
        }
    }

    @Test
    func presenceOfflineEventRemovesFromPresenceStore() async throws {
        try await withFixture { fixture in
            fixture.session.presenceStore.setOnline(7)
            fixture.session.wsClient._dispatchForTesting(
                .presenceOffline(UserIdPayload(userId: 7))
            )
            #expect(!fixture.session.presenceStore.isOnline(7))
        }
    }

    @Test
    func typingStartEventInsertsIntoTypingStore() async throws {
        try await withFixture { fixture in
            fixture.session.wsClient._dispatchForTesting(
                .typingStart(ConversationUserPayload(conversationId: 42, userId: 7))
            )
            #expect(fixture.session.typingStore.isTyping(42))
        }
    }

    @Test
    func typingStopEventRemovesFromTypingStore() async throws {
        try await withFixture { fixture in
            fixture.session.typingStore.handleTypingStart(conversationId: 42)
            fixture.session.wsClient._dispatchForTesting(
                .typingStop(ConversationUserPayload(conversationId: 42, userId: 7))
            )
            #expect(!fixture.session.typingStore.isTyping(42))
        }
    }

    @Test
    func wsReadyClearsPresenceStore() async throws {
        try await withFixture { fixture in
            fixture.session.presenceStore.setOnline(1)
            fixture.session.presenceStore.setOnline(2)
            fixture.session.wsClient._fireReadyForTesting()
            #expect(fixture.session.presenceStore.onlineUserIds.isEmpty)
        }
    }

    @Test
    func wsReadyClearsBeforeSubsequentPresenceOnlineEvents() async throws {
        // 模拟服务端真实顺序：先 connection.ready，再多条 presence.online
        try await withFixture { fixture in
            fixture.session.presenceStore.setOnline(99)         // 旧的脏数据，模拟离线期累积

            fixture.session.wsClient._fireReadyForTesting()
            fixture.session.wsClient._dispatchForTesting(
                .presenceOnline(UserIdPayload(userId: 1))
            )
            fixture.session.wsClient._dispatchForTesting(
                .presenceOnline(UserIdPayload(userId: 2))
            )

            #expect(fixture.session.presenceStore.onlineUserIds == [1, 2])
            #expect(!fixture.session.presenceStore.isOnline(99))
        }
    }
}
```

> 选用 `withFixture` helper 而不是 `defer { Task { ... } }` 的原因：`defer` 里起 detached `Task` 是 fire-and-forget——测试 return 时清理动作可能还没跑完，进程退出甚至会直接丢任务。`withFixture` 形式让清理永远 await 到位，且 try 失败路径也走同一份清理。代价是 body 多一层缩进，可接受。

> 旧版（已废弃）：使用固定 `userId: 100` 会污染 `~/Library/Developer/CoreSimulator/.../Application Support/EchoIM/users/100/` 目录，且并行测试会撞库。务必走 `makeFixture()` 路径。

- [x] **Step 2: 给 WebSocketClient 加 DEBUG 测试入口**

> 已在 Task 3 中提前实现，此处确认存在。

在 `ios-app/EchoIM/Core/Networking/WebSocketClient.swift` 文件末尾追加：

```swift
#if DEBUG
extension WebSocketClient {
    /// 仅测试用：直接 dispatch 一条 WSEvent 给所有订阅者，不走真实 receive 路径。
    func _dispatchForTesting(_ event: WSEvent) {
        for handler in handlers.values {
            handler(event)
        }
    }

    /// 仅测试用：直接触发 onReady 回调（不切 state 也不 startHeartbeat，只跑 readyHandlers）。
    /// 模拟"服务端 connection.ready 已到达"。
    func _fireReadyForTesting() {
        for handler in Array(readyHandlers.values) {
            handler()
        }
    }
}
#endif
```

- [x] **Step 3: 跑测试，确认失败（UserSession 还没暴露 stores 也没 attach 订阅）**

Run: `$TEST -only-testing:EchoIMTests/UserSessionRoutingTests`
Expected: 编译失败（`session.presenceStore` / `session.typingStore` 不存在）。

- [x] **Step 4: 实现 UserSession 路由订阅**

修改 `ios-app/EchoIM/App/UserSession.swift`：

在 stored properties 区追加：

```swift
let presenceStore: PresenceStore
let typingStore: TypingStore
private var routingSubscriptions: [WSSubscription] = []
```

在 `init` 体里，紧跟在创建 `wsClient` 之后追加：

```swift
self.presenceStore = PresenceStore()
self.typingStore = TypingStore()

// 把 wsClient 上的事件路由到对应 store。store 自身不订阅 wsClient（不变式 1）。
routingSubscriptions.append(
    wsClient.subscribe { [presenceStore, typingStore] event in
        switch event {
        case .presenceOnline(let payload):
            presenceStore.setOnline(payload.userId)
        case .presenceOffline(let payload):
            presenceStore.setOffline(payload.userId)
        case .typingStart(let payload):
            typingStore.handleTypingStart(conversationId: payload.conversationId)
        case .typingStop(let payload):
            typingStore.handleTypingStop(conversationId: payload.conversationId)
        default:
            break
        }
    }
)
routingSubscriptions.append(
    wsClient.onReady { [presenceStore] in
        // 设计 §7.5 step 5：先清空，让后续 presence.online 重建集合。
        presenceStore.clearAll()
    }
)
```

> **注意**：`presenceStore` / `typingStore` 都是 `@MainActor` 类，闭包捕获 list 里写 `[presenceStore, typingStore]`（按值捕获引用）即可，调用方无需再额外标 `@MainActor`——闭包本身会在 `WebSocketClient` 的 `@MainActor` 上下文里跑（subscribe handler 的派发在主线程，已经验证）。

也加一个发送 typing 的便捷方法（Task 6 / Task 9 用）：

```swift
func sendTyping(conversationId: Int, isStart: Bool) {
    wsClient.sendTyping(conversationId: conversationId, isStart: isStart)
}
```

- [x] **Step 5: 跑测试，确认通过**

Run: `$TEST -only-testing:EchoIMTests/UserSessionRoutingTests`
Expected: 6 条全过。✅ 实际：6 条全过。

- [x] **Step 6: 跑全量单测确认无回归**

Run: `$TEST`
Expected: 与 P5 末态相比，仅多出本任务新增的测试。✅ 全量通过（含 TypingStoreTests timing fix）。

- [x] **Step 7: 提交**

```bash
git add ios-app/EchoIM/App/UserSession.swift \
         ios-app/EchoIM/Core/Networking/WebSocketClient.swift \
         ios-app/EchoIMTests/UserSessionRoutingTests.swift
git commit -m "feat(ios): wire presence/typing event routing on UserSession"
```

---

## Task 5: ChatViewModel 注入 typingStore + 暴露 peerIsTyping（不路由事件）✅

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`
- Test: `ios-app/EchoIMTests/ChatViewModelPresenceTests.swift`

设计依据：§4.3（`typingPeers: Set<Int>`）+ 不变式 8（VM 不重复路由 typing/presence）。架构选择：**不在 ChatViewModel 里维护自己的 typingPeers 集合，也不在 `handleWSEvent` 里调 `typingStore` / `presenceStore`**——UserSession（Task 4）已是唯一写入方。VM 只**读** `typingStore.isTyping(conversationId)` 渲染就行。这样既避免双写，也保证多个并发 ChatView（理论上不会有，但防御）共享同一份权威状态。`handleWSEvent` 的 `default: return` 分支保持原样不动。

ChatViewModel 新增依赖 `private let typingStore: TypingStore?`（可空便于 P5 现有测试不改动），渲染时通过 `vm.peerIsTyping` 计算属性拉取。

> **实现说明**：测试文件中的 `NoopMessageRepository` 命名为 `PresenceNoopMessageRepository` 以避免与其他测试文件（Task 6 的 `NoopMessageRepository2`）在同模块内重名（Swift `private` 在文件作用域有效但模块内名字相同仍会有警告）。

- [x] **Step 1: 写测试 — peerIsTyping 计算属性 + handleWSEvent 对 typing/presence 保持 no-op（路由由 UserSession 负责，VM 不双写）**

```swift
// ios-app/EchoIMTests/ChatViewModelPresenceTests.swift
import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite
struct ChatViewModelPresenceTests {
    @Test
    func peerIsTypingReflectsTypingStoreState() {
        let typingStore = TypingStore(safetyDuration: 5.0)
        let vm = makeVM(conversationId: 42, typingStore: typingStore)

        #expect(!vm.peerIsTyping)
        typingStore.handleTypingStart(conversationId: 42)
        #expect(vm.peerIsTyping)
        typingStore.handleTypingStop(conversationId: 42)
        #expect(!vm.peerIsTyping)
    }

    @Test
    func peerIsTypingFalseWhenConversationIdNil() {
        let typingStore = TypingStore(safetyDuration: 5.0)
        let vm = makeVM(conversationId: nil, typingStore: typingStore)
        // 草稿态——typingStore 里有别的会话也无关
        typingStore.handleTypingStart(conversationId: 99)
        #expect(!vm.peerIsTyping)
    }

    @Test
    func peerIsTypingIgnoresOtherConversations() {
        let typingStore = TypingStore(safetyDuration: 5.0)
        let vm = makeVM(conversationId: 42, typingStore: typingStore)
        typingStore.handleTypingStart(conversationId: 999)
        #expect(!vm.peerIsTyping)
    }

    @Test
    func handleWSEventIgnoresTypingForOtherConversation() {
        // typing/presence 路由由 UserSession 负责（不变式 1 + 8）——
        // ChatViewModel 的 handleWSEvent 必须对这类事件保持 no-op；
        // 这里验证 VM 不重复写 typingStore（避免双计）。
        let typingStore = TypingStore(safetyDuration: 5.0)
        let vm = makeVM(conversationId: 42, typingStore: typingStore)
        vm.handleWSEvent(
            .typingStart(ConversationUserPayload(conversationId: 99, userId: 7))
        )
        #expect(!typingStore.isTyping(99), "ChatViewModel must not re-route typing events to typingStore — UserSession is the only writer")
    }

    // MARK: - Helpers

    private func makeVM(
        conversationId: Int?,
        typingStore: TypingStore
    ) -> ChatViewModel {
        let route: ChatRoute
        if let conversationId {
            route = .conversation(
                Conversation(
                    id: conversationId,
                    createdAt: Date(),
                    peer: UserProfile(id: 7, username: "alice", displayName: nil, avatarUrl: nil),
                    lastMessageBody: nil,
                    lastMessageType: nil,
                    lastMessageSenderId: nil,
                    lastMessageAt: nil,
                    lastReadMessageId: nil,
                    unreadCount: 0
                )
            )
        } else {
            route = .peer(
                UserProfile(id: 7, username: "alice", displayName: nil, avatarUrl: nil)
            )
        }
        return ChatViewModel(
            route: route,
            currentUserId: 100,
            messageRepo: NoopMessageRepository(),
            wsClient: nil,
            typingStore: typingStore,
            tokenProvider: { "tok" }
        )
    }
}

private struct NoopMessageRepository: MessageRepository {
    func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] { [] }
    func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
        throw URLError(.badServerResponse)
    }
    func sendImage(recipientId: Int, mediaUrl: String, clientTempId: String, token: String) async throws -> Message {
        throw URLError(.badServerResponse)
    }
    func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
}
```

> 注意：上面的 `NoopMessageRepository` 与现有 `ChatViewModelImageTests` 等测试文件已有的 mock 重复。如果改造后构造空 mock 太长，把它合并到 `ImageTestHelpers.swift` 里，但对 P6 不强求——P6 的核心是 typingStore 注入路径，不是 mock 整理。如果文件膨胀超过 80 行考虑下提，但不是阻塞项。

- [x] **Step 2: 跑测试，确认失败（`ChatViewModel` 还没接受 `typingStore` 参数也没 `peerIsTyping` 属性）**

Run: `$TEST -only-testing:EchoIMTests/ChatViewModelPresenceTests`
Expected: 编译失败。

- [x] **Step 3: 改造 `ChatViewModel`**

`ios-app/EchoIM/Features/Chat/ChatViewModel.swift`：

1) 加 stored property：

```swift
private let typingStore: TypingStore?
```

2) `init` 增加参数：

```swift
init(
    route: ChatRoute,
    currentUserId: Int,
    messageRepo: MessageRepository,
    wsClient: WebSocketClient?,
    conversationRepository: ConversationRepository? = nil,
    messageStore: MessageStore? = nil,
    metaStore: ConversationMetaStore? = nil,
    uploadRepo: UploadRepository? = nil,
    typingStore: TypingStore? = nil,
    tokenProvider: @escaping @MainActor () -> String?
) {
    // ... existing assignments ...
    self.typingStore = typingStore
    // ... existing tail ...
}
```

3) 加计算属性（放在 `// MARK: - Identity` 区下方或 `// MARK: - State` 区里）：

```swift
/// 对方是否正在输入。仅当 conversationId 已知且 typingStore 命中时为 true。
var peerIsTyping: Bool {
    guard let conversationId, let typingStore else { return false }
    return typingStore.isTyping(conversationId)
}
```

4) `handleWSEvent` 的 default 分支保持不变（**ChatViewModel 不重复路由 typing / presence**——UserSession 已是唯一写入方）。这条不变式靠测试 `handleWSEventIgnoresTypingForOtherConversation` 锁住。

- [x] **Step 4: 跑测试**

Run: `$TEST -only-testing:EchoIMTests/ChatViewModelPresenceTests`
Expected: 4 条全过。✅

- [x] **Step 5: 跑全量 ChatViewModel 测试避免回归**

Expected: 所有现有测试不变（typingStore 默认 nil）。✅ 全量 ChatViewModel 测试通过。

- [x] **Step 6: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
         ios-app/EchoIMTests/ChatViewModelPresenceTests.swift
git commit -m "feat(ios): add peerIsTyping wiring on ChatViewModel"
```

---

## Task 6: ChatViewModel 输入 debounce 发送 typing.start / typing.stop ✅

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`
- Test: `ios-app/EchoIMTests/ChatViewModelTypingTests.swift`

设计依据：§8 P6 "本端 debounce 发 typing.start / typing.stop" + 不变式 4 / 5（三种触发点都发 stop；start dedupe）。

实现策略（与 Web `ChatView.tsx:276-307` 对齐）：
- VM 加状态 `private var typingSendActive = false` + `private var idleTimer: Task<Void, Never>?`
- VM 加方法 `func handleTypingInput()` / `func stopTyping()`
- VM 加注入 `private let typingSender: @MainActor (Int, Bool) -> Void`（默认 `{ _, _ in }`，生产代码注入 `[weak ws] cid, isStart in ws?.sendTyping(...)`）
- VM 加注入 `private let idleDuration: TimeInterval`（默认 3.0，单测 0.05）

**关键**：sendText 路径里成功 / 失败都调 stopTyping；ChatView 的 `onDisappear` 也调 stopTyping。

- [x] **Step 1: 写测试**

> **实现说明**：测试中 idle 定时器用 0.10s + 等待 0.5s（与 TypingStore 同样的 timing 加固策略），避免并行运行时 flaky。NoopMessageRepository 命名为 `TypingNoopMessageRepository` 避免跨文件符号冲突。

```swift
// ios-app/EchoIMTests/ChatViewModelTypingTests.swift
import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite
struct ChatViewModelTypingTests {
    @Test
    func firstInputSendsTypingStart() {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: 42, recorder: recorder, idleDuration: 5.0)
        vm.handleTypingInput()
        #expect(recorder.calls == [TypingCall(conversationId: 42, isStart: true)])
    }

    @Test
    func consecutiveInputsDoNotResendStart() {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: 42, recorder: recorder, idleDuration: 5.0)
        vm.handleTypingInput()
        vm.handleTypingInput()
        vm.handleTypingInput()
        // start 只发一次（dedupe），idle 计时器被反复重置但不重发。
        #expect(recorder.calls == [TypingCall(conversationId: 42, isStart: true)])
    }

    @Test
    func idleTimeoutSendsTypingStop() async throws {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: 42, recorder: recorder, idleDuration: 0.05)
        vm.handleTypingInput()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(recorder.calls == [
            TypingCall(conversationId: 42, isStart: true),
            TypingCall(conversationId: 42, isStart: false),
        ])
    }

    @Test
    func subsequentInputAfterIdleStopRestartsCycle() async throws {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: 42, recorder: recorder, idleDuration: 0.05)
        vm.handleTypingInput()
        try await Task.sleep(nanoseconds: 200_000_000)
        vm.handleTypingInput()
        // 第二轮——又发一次 start
        #expect(recorder.calls == [
            TypingCall(conversationId: 42, isStart: true),
            TypingCall(conversationId: 42, isStart: false),
            TypingCall(conversationId: 42, isStart: true),
        ])
    }

    @Test
    func explicitStopTypingSendsStopImmediately() {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: 42, recorder: recorder, idleDuration: 5.0)
        vm.handleTypingInput()
        vm.stopTyping()
        #expect(recorder.calls == [
            TypingCall(conversationId: 42, isStart: true),
            TypingCall(conversationId: 42, isStart: false),
        ])
    }

    @Test
    func stopTypingWithoutActiveDoesNotSend() {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: 42, recorder: recorder, idleDuration: 5.0)
        vm.stopTyping()
        #expect(recorder.calls.isEmpty)
    }

    @Test
    func handleTypingInputIgnoredWhenConversationIdNil() {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: nil, recorder: recorder, idleDuration: 5.0)
        vm.handleTypingInput()
        // 草稿态没有 conversationId 可绑定
        #expect(recorder.calls.isEmpty)
    }

    // MARK: - Helpers

    struct TypingCall: Equatable {
        let conversationId: Int
        let isStart: Bool
    }

    @MainActor
    final class TypingRecorder {
        var calls: [TypingCall] = []
        func record(_ conversationId: Int, _ isStart: Bool) {
            calls.append(TypingCall(conversationId: conversationId, isStart: isStart))
        }
    }

    private func makeVM(
        conversationId: Int?,
        recorder: TypingRecorder,
        idleDuration: TimeInterval
    ) -> ChatViewModel {
        let route: ChatRoute
        if let conversationId {
            route = .conversation(
                Conversation(
                    id: conversationId,
                    createdAt: Date(),
                    peer: UserProfile(id: 7, username: "alice", displayName: nil, avatarUrl: nil),
                    lastMessageBody: nil,
                    lastMessageType: nil,
                    lastMessageSenderId: nil,
                    lastMessageAt: nil,
                    lastReadMessageId: nil,
                    unreadCount: 0
                )
            )
        } else {
            route = .peer(
                UserProfile(id: 7, username: "alice", displayName: nil, avatarUrl: nil)
            )
        }
        return ChatViewModel(
            route: route,
            currentUserId: 100,
            messageRepo: NoopMessageRepository2(),
            wsClient: nil,
            typingSender: { cid, isStart in recorder.record(cid, isStart) },
            idleTypingDuration: idleDuration,
            tokenProvider: { "tok" }
        )
    }
}

private struct NoopMessageRepository2: MessageRepository {
    func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] { [] }
    func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
        throw URLError(.badServerResponse)
    }
    func sendImage(recipientId: Int, mediaUrl: String, clientTempId: String, token: String) async throws -> Message {
        throw URLError(.badServerResponse)
    }
    func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
}
```

- [x] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/ChatViewModelTypingTests`
Expected: 编译失败（`typingSender` / `idleTypingDuration` / `handleTypingInput` / `stopTyping` 不存在）。

- [x] **Step 3: 改造 ChatViewModel**

`ios-app/EchoIM/Features/Chat/ChatViewModel.swift`：

1) 加 stored property：

```swift
private let typingSender: @MainActor (Int, Bool) -> Void
private let idleTypingDuration: TimeInterval
private var typingSendActive = false
private var idleTypingTimer: Task<Void, Never>?
```

2) `init` 增加参数（在已有的 `typingStore` / `tokenProvider` 之间或前后插入即可——保留默认值不破坏 P5 调用方）：

```swift
init(
    route: ChatRoute,
    currentUserId: Int,
    messageRepo: MessageRepository,
    wsClient: WebSocketClient?,
    conversationRepository: ConversationRepository? = nil,
    messageStore: MessageStore? = nil,
    metaStore: ConversationMetaStore? = nil,
    uploadRepo: UploadRepository? = nil,
    typingStore: TypingStore? = nil,
    typingSender: @escaping @MainActor (Int, Bool) -> Void = { _, _ in },
    idleTypingDuration: TimeInterval = 3.0,
    tokenProvider: @escaping @MainActor () -> String?
) {
    // ... 已有赋值 ...
    self.typingSender = typingSender
    self.idleTypingDuration = idleTypingDuration
    // ... 现有尾部 ...
}
```

3) 加方法（在 `// MARK: - WS` 区前/后另起 `// MARK: - Typing` 区）：

```swift
// MARK: - Typing

/// 输入框 onChange 时调用：第一次发 start，重置 3 秒 idle 兜底定时器。
/// 不变式 5：连续按键不重复发 start，依赖 typingSendActive 标志去重。
func handleTypingInput() {
    guard let conversationId else { return }

    if !typingSendActive {
        typingSendActive = true
        typingSender(conversationId, true)
    }

    idleTypingTimer?.cancel()
    let nanos = UInt64(idleTypingDuration * 1_000_000_000)
    idleTypingTimer = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: nanos)
        guard !Task.isCancelled, let self else { return }
        self.stopTyping()
    }
}

/// 三种触发点都调（不变式 4）：
/// 1. idle 3 秒兜底
/// 2. sendText / sendImage 完成（成功 / 失败）
/// 3. ChatView.onDisappear
func stopTyping() {
    idleTypingTimer?.cancel()
    idleTypingTimer = nil

    guard typingSendActive, let conversationId else { return }
    typingSendActive = false
    typingSender(conversationId, false)
}
```

4) `sendText` / `sendImage` / `sendCompressedImage` 入口立即 stopTyping（**必须在所有 guard 之前**——token / uploadRepo 缺失时也要停 typing，否则用户进入失败路径但对方仍卡在"正在输入"）：

```swift
func sendText(_ body: String) async {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }    // 空 body 不算"按发送"，无需 stopTyping

    stopTyping()    // 不变式 4 触发点 ②；必须早于 token guard，避免 401 早退漏发 stop

    guard let token = tokenProvider() else { return }
    // ... 既有路径不变 ...
}

func sendImage(_ image: UIImage) async {
    stopTyping()    // 不变式 4 触发点 ②；必须早于 ImageCompressor 早退

    guard let compressed = ImageCompressor.compressForUpload(image) else {
        return
    }
    await sendCompressedImage(data: compressed.data, width: compressed.width, height: compressed.height)
}

func sendCompressedImage(data: Data, width: Int, height: Int) async {
    // 注意：sendImage 已经调过 stopTyping；sendCompressedImage 直接被调用（如测试）也要再调一次保证幂等。
    stopTyping()

    guard let token = tokenProvider() else { return }
    guard let uploadRepo else { return }
    // ... 既有路径不变 ...
}
```

> 早退场景里 `stopTyping()` 是幂等的（`typingSendActive == false` 时直接 return），重复调用零代价。空 body 的 `sendText` 不调 stopTyping 是因为它根本没"按发送"——空字符串通常是输入框被清空到空再失焦，typing 状态由别处的 onChange/onDisappear 收尾。

- [x] **Step 4: 跑测试**

Run: `$TEST -only-testing:EchoIMTests/ChatViewModelTypingTests`
Expected: 7 条全过。✅

- [x] **Step 5: 跑全量 ChatViewModel 测试避免回归**

Expected: 不变。✅ ChatViewModelSendTests 全过。

- [x] **Step 6: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
         ios-app/EchoIMTests/ChatViewModelTypingTests.swift
git commit -m "feat(ios): add typing input debounce on ChatViewModel"
```

---

## Task 7: PresenceDot 视图组件 ✅

**Files:**
- Create: `ios-app/EchoIM/Core/UI/PresenceDot.swift`

设计依据：好友列表 / 会话列表 / 聊天页顶部三处渲染同一个圆点。SwiftUI 没有内置 status indicator，自己封装：默认 10pt 绿点 + 1.5pt 白边（在深色头像 / 浅色背景下都可见），尺寸通过 `size` / `borderWidth` 参数可调——聊天页 header 显式传 `PresenceDot(size: 8)` 配 inline title 区更协调。是纯渲染组件，不持 store——上层基于 `presenceStore.isOnline(userId)` 决定渲不渲染。

> 没有 TDD 单测——纯视图。手工 + smoke。

- [ ] **Step 1: 创建文件**

```swift
// ios-app/EchoIM/Core/UI/PresenceDot.swift
import SwiftUI

/// 好友 / 会话 / 聊天页头部用的"在线"圆点。
/// 颜色固定为绿色（系统语义 .green），边框白色保证在头像和深色背景上都可见。
/// 调用方负责决定显示与否（基于 PresenceStore），并放在合适的相对位置（一般是头像右下角 overlay）。
struct PresenceDot: View {
    var size: CGFloat = 10
    var borderWidth: CGFloat = 1.5

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color(uiColor: .systemBackground), lineWidth: borderWidth)
            )
            .accessibilityLabel("在线")
            .accessibilityHidden(false)
    }
}

#Preview {
    HStack(spacing: 16) {
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(.gray).frame(width: 40, height: 40)
            PresenceDot().offset(x: 2, y: 2)
        }
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(.blue).frame(width: 56, height: 56)
            PresenceDot(size: 14).offset(x: 2, y: 2)
        }
    }
    .padding()
}
```

- [x] **Step 2: 编译**

Run: `$BUILD`
Expected: 通过。✅

- [x] **Step 3: 模拟器手工预览（可选）**

打开 Xcode → 文件 → Canvas Preview，确认两种尺寸圆点都正常显示。

- [x] **Step 4: 提交**

```bash
git add ios-app/EchoIM/Core/UI/PresenceDot.swift
git commit -m "feat(ios): add PresenceDot view"
```

---

## Task 8: FriendsListView / ConversationsListView 加在线圆点

**Files:**
- Modify: `ios-app/EchoIM/Features/Contacts/FriendsListView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/ContactsView.swift`（透传 presenceStore）
- Modify: `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`
- Modify: `ios-app/EchoIM/Features/Main/MainTabView.swift`（透传 presenceStore）

设计依据：§8 P6 "好友列表 + 会话列表 + 聊天页顶部在线圆点"。

为了让 `@Observable` 的 `presenceStore` 在变更时触发列表行重渲染，传入 view 的最干净方式是按值传引用（`PresenceStore` 是 `final class` 的引用类型；`@Observable` 自动生效）。

- [ ] **Step 1: FriendsListView 增加 presenceStore 入参，行内插入 PresenceDot**

```swift
// ios-app/EchoIM/Features/Contacts/FriendsListView.swift
import SwiftUI

struct FriendsListView: View {
    let friends: [Friend]
    /// P6：传 nil 时不显示圆点。**显式 `= nil` 默认值**让 P5 既有调用 `FriendsListView(friends: x)`
    /// 不需要改造，由 SwiftUI 自动合成的 memberwise init 用 nil 兜底。
    let presenceStore: PresenceStore? = nil

    var body: some View {
        if friends.isEmpty {
            emptyState
        } else {
            List(friends) { friend in
                NavigationLink(value: ChatRoute.peer(friend)) {
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarView(profile: friend, size: 40)
                            if presenceStore?.isOnline(friend.id) == true {
                                PresenceDot()
                                    .offset(x: 2, y: 2)
                                    .accessibilityIdentifier("friendOnlineDot_\(friend.username)")
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayTitle)
                                .font(.subheadline.weight(.medium))

                            if let usernameSubtitle = friend.usernameSubtitle {
                                Text(usernameSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                }
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("friendRow_\(friend.username)")
            }
            .listStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("friendsList")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("还没有好友")
                .foregroundStyle(.secondary)
            Text("点右上角 + 搜索用户添加好友")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friendsEmpty")
    }
}
```

- [ ] **Step 2: ContactsView 透传 presenceStore + typingStore + typingSender**

`ios-app/EchoIM/Features/Contacts/ContactsView.swift`：
- 加 stored property：`private let presenceStore: PresenceStore?` / `private let typingStore: TypingStore?` / `private let typingSender: @MainActor (Int, Bool) -> Void`
- init 接收三个新参数
- body 里 `FriendsListView(friends: vm.friends)` 改成 `FriendsListView(friends: vm.friends, presenceStore: presenceStore)`
- `.navigationDestination` 里调 `ChatView(...)` 时透传 `presenceStore` / `typingStore` / `typingSender`（具体调用形态在 Task 9 Step 2）

```swift
// 关键改动片段。三个新参数都带默认值，避免破坏 P5 既有调用方
// （MainTabView 之外是否还有别的入口需扫一遍——当前仓库中只有 MainTabView 一处）。
init(
    friendRepo: FriendRepository,
    requestRepo: FriendRequestRepository,
    userRepo: UserRepository,
    messageRepo: MessageRepository,
    conversationRepo: ConversationRepository,
    messageStore: MessageStore?,
    metaStore: ConversationMetaStore?,
    wsClient: WebSocketClient?,
    uploadRepo: UploadRepository,
    currentUserId: Int,
    presenceStore: PresenceStore? = nil,
    typingStore: TypingStore? = nil,
    typingSender: @escaping @MainActor (Int, Bool) -> Void = { _, _ in },
    tokenProvider: @escaping () -> String?
) {
    // ... 已有赋值 ...
    self.presenceStore = presenceStore
    self.typingStore = typingStore
    self.typingSender = typingSender
    // ... 现有尾部 ...
}
```

```swift
// body 里：
FriendsListView(friends: vm.friends, presenceStore: presenceStore)
```

- [ ] **Step 3: ConversationsListView 行内插入 PresenceDot**

`ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`：
- `init` 增加三个新参数（都带默认值兼容 P5 既有 spawn 路径）：

  ```swift
  init(
      // ... 已有参数 ...
      presenceStore: PresenceStore? = nil,
      typingStore: TypingStore? = nil,
      typingSender: @escaping @MainActor (Int, Bool) -> Void = { _, _ in },
      tokenProvider: @escaping @MainActor () -> String?
  ) {
      // ... 已有赋值 ...
      self.presenceStore = presenceStore
      self.typingStore = typingStore
      self.typingSender = typingSender
  }
  ```

- 加 stored property：`private let presenceStore: PresenceStore?` / `private let typingStore: TypingStore?` / `private let typingSender: @MainActor (Int, Bool) -> Void`
- `ConversationRow` 也加 `let presenceStore: PresenceStore? = nil`（同样 SwiftUI memberwise init 默认 nil），把 `AvatarView(profile: ..., size: 44)` 包到 ZStack 里：

```swift
// ConversationRow body 头部：
HStack(spacing: 12) {
    ZStack(alignment: .bottomTrailing) {
        AvatarView(profile: conversation.peer, size: 44)
        if presenceStore?.isOnline(conversation.peer.id) == true {
            PresenceDot()
                .offset(x: 2, y: 2)
                .accessibilityIdentifier("conversationOnlineDot_\(conversation.peer.username)")
        }
    }
    // ... rest unchanged ...
}
```

- list view 调用 ConversationRow 处也要把 presenceStore 传进去：

```swift
List(vm.conversations) { conversation in
    NavigationLink(value: ChatRoute.conversation(conversation)) {
        ConversationRow(conversation: conversation, presenceStore: presenceStore)
    }
    .listRowSeparator(.hidden)
    .listRowInsets(
        EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
    )
}
```

- [ ] **Step 4: MainTabView 透传 presenceStore 到两个 tab**

`ios-app/EchoIM/Features/Main/MainTabView.swift` 里 `chatsTab` / `contactsTab` 计算属性都改造：

```swift
@ViewBuilder
private var chatsTab: some View {
    if let session = container.session {
        ConversationsListView(
            repository: session.makeConversationRepository(),
            messageRepo: session.makeMessageRepository(),
            metaStore: session.conversationMetaStore(),
            messageStore: session.messageStore(),
            wsClient: session.wsClient,
            uploadRepo: session.makeUploadRepository(),
            currentUserId: container.currentUser?.id ?? 0,
            presenceStore: session.presenceStore,
            typingStore: session.typingStore,
            typingSender: { [weak ws = session.wsClient] cid, isStart in
                ws?.sendTyping(conversationId: cid, isStart: isStart)
            },
            tokenProvider: { [tokenStore = container.tokenStore] in
                (try? tokenStore.load())?.token
            }
        )
    } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`contactsTab` 类似——给 `ContactsView(...)` 也加 `presenceStore: session.presenceStore` + `typingStore: session.typingStore` + `typingSender: { [weak ws = session.wsClient] cid, isStart in ws?.sendTyping(conversationId: cid, isStart: isStart) }` 三个新参数（typingStore / typingSender 是给 ChatView 用的，沿着 ChatRoute 一路下传，下一个 Task 处理 ChatView 注入）。

- [ ] **Step 5: 编译 + UI 测试不退化**

Run: `$BUILD` 期望通过。
Run: `$TEST` 期望通过。`FriendsListView` 的 `presenceStore` 写成 `let presenceStore: PresenceStore? = nil`——SwiftUI 自动合成的 memberwise init 把它表达成可选参数 + 默认 nil，所以 P5 既有调用 `FriendsListView(friends: x)` 不需要改；新增的调用 `FriendsListView(friends: vm.friends, presenceStore: presenceStore)` 走显式参数赋值。`ContactsView` / `ConversationsListView` 的新参数也按相同模式（`= nil` 或 `{ _, _ in }` 默认）声明，新增的 `typingSender` 给个空闭包默认值即可。

> 这里需要 audit 现有 UI 测试是否引用 `FriendsListView` / `ContactsView` / `ConversationsListView` 的 init。`FriendRequestCrossAccountSmokeTests` / `TabNavigationSmokeTests` 用的是 RootView 入口，不直接 init view，应不受影响。

- [ ] **Step 6: 提交**

```bash
git add ios-app/EchoIM/Features/Contacts/FriendsListView.swift \
         ios-app/EchoIM/Features/Contacts/ContactsView.swift \
         ios-app/EchoIM/Features/Conversations/ConversationsListView.swift \
         ios-app/EchoIM/Features/Main/MainTabView.swift
git commit -m "feat(ios): show presence dot on friends and conversation rows"
```

---

## Task 9: ChatView 顶部 principal 视图（昵称 + 圆点 + 正在输入...）+ 注入 typingStore / typingSender

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatView.swift`
- Modify: `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`（destination 调 ChatView 的入参）
- Modify: `ios-app/EchoIM/Features/Contacts/ContactsView.swift`（同上，从联系人进入草稿聊天）

设计依据：§8 P6 "聊天页顶部在线圆点 / 正在输入..."。原 `.navigationTitle(vm.peer.displayTitle)` 不能放圆点；改成 `.toolbar(.principal)` 自定义两行视图：上行 `peer 名 · 圆点（条件渲染）`，下行 `子标题（typing 时显示"正在输入..."，否则空）`。

ChatView init 增加 `presenceStore: PresenceStore?` / `typingStore: TypingStore?` / `typingSender: @MainActor (Int, Bool) -> Void = { _, _ in }` 三个入参，前两个透传给 view 内自管理，typingSender 注入 VM。

- [ ] **Step 1: 改造 ChatView**

```swift
// ios-app/EchoIM/Features/Chat/ChatView.swift
import PhotosUI
import SwiftUI
import UIKit

struct ChatView: View {
    @State private var vm: ChatViewModel
    @State private var draft = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var lightboxBubble: LocalMessage?
    private let presenceStore: PresenceStore?

    init(
        route: ChatRoute,
        currentUserId: Int,
        messageRepo: MessageRepository,
        messageStore: MessageStore?,
        metaStore: ConversationMetaStore?,
        wsClient: WebSocketClient?,
        conversationRepository: ConversationRepository?,
        uploadRepo: UploadRepository,
        presenceStore: PresenceStore? = nil,
        typingStore: TypingStore? = nil,
        typingSender: @escaping @MainActor (Int, Bool) -> Void = { _, _ in },
        tokenProvider: @escaping @MainActor () -> String?
    ) {
        _vm = State(
            wrappedValue: ChatViewModel(
                route: route,
                currentUserId: currentUserId,
                messageRepo: messageRepo,
                wsClient: wsClient,
                conversationRepository: conversationRepository,
                messageStore: messageStore,
                metaStore: metaStore,
                uploadRepo: uploadRepo,
                typingStore: typingStore,
                typingSender: typingSender,
                tokenProvider: tokenProvider
            )
        )
        self.presenceStore = presenceStore
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            Divider()
            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                principalTitle
            }
        }
        .task {
            vm.attachWSSubscription()
            await vm.load()
        }
        .onDisappear {
            vm.stopTyping()                  // 不变式 4 触发点 ③
            vm.detachWSSubscription()
        }
        .onChange(of: pickedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await handlePickedItem(newItem)
                pickedItem = nil
            }
        }
        .fullScreenCover(item: $lightboxBubble) { bubble in
            Lightbox(
                localData: bubble.localImageData,
                remoteURL: Endpoints.absolute(bubble.message.mediaUrl),
                onClose: { lightboxBubble = nil }
            )
        }
    }

    private var principalTitle: some View {
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chatPrincipalTitle")
    }

    private var messagesList: some View {
        // ... 既有实现不变 ...
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .regular))
            }
            .accessibilityLabel("发送图片")
            .accessibilityIdentifier("chatImagePicker")

            TextField("说点什么...", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onChange(of: draft) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        vm.stopTyping()
                    } else {
                        vm.handleTypingInput()
                    }
                }
                .accessibilityIdentifier("chatInput")

            Button {
                let text = draft
                draft = ""
                Task {
                    await vm.sendText(text)
                }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSend)
            .accessibilityLabel("发送")
            .accessibilityIdentifier("chatSend")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        await vm.sendImage(image)
    }
}
```

> 保留原 `messagesList` 实现不变（这里省略不重写）。

- [ ] **Step 2: 调用方更新（ConversationsListView 的 destination + ContactsView 的草稿入口）**

`ConversationsListView.swift` 里 `destination(for:)` 改造：

```swift
private func destination(for route: ChatRoute) -> some View {
    ChatView(
        route: route,
        currentUserId: currentUserId,
        messageRepo: messageRepo,
        messageStore: messageStore,
        metaStore: metaStore,
        wsClient: wsClient,
        conversationRepository: conversationRepo,
        uploadRepo: uploadRepo,
        presenceStore: presenceStore,
        typingStore: typingStore,
        typingSender: typingSender,
        tokenProvider: { tokenProvider() }
    )
}
```

> 上面新增的 `typingStore` / `typingSender` 需要 ConversationsListView init 也跟着接收，并由 MainTabView 透传——已在 Task 8 Step 4 中预演过。

`ContactsView.swift` 里 `.navigationDestination(for: ChatRoute.self)` 块现在是这样（参考行号附近 `ContactsView.swift:91-105`）：

```swift
.navigationDestination(for: ChatRoute.self) { route in
    ChatView(
        route: route,
        currentUserId: currentUserId,
        messageRepo: messageRepo,
        messageStore: messageStore,
        metaStore: metaStore,
        wsClient: wsClient,
        conversationRepository: conversationRepo,
        uploadRepo: uploadRepo,
        tokenProvider: { tokenProvider() }
    )
}
```

改成（多三个参数，从 Step 2 注入的 stored property 取）：

```swift
.navigationDestination(for: ChatRoute.self) { route in
    ChatView(
        route: route,
        currentUserId: currentUserId,
        messageRepo: messageRepo,
        messageStore: messageStore,
        metaStore: metaStore,
        wsClient: wsClient,
        conversationRepository: conversationRepo,
        uploadRepo: uploadRepo,
        presenceStore: presenceStore,
        typingStore: typingStore,
        typingSender: typingSender,
        tokenProvider: { tokenProvider() }
    )
}
```

- [ ] **Step 3: 编译**

Run: `$BUILD`
Expected: 通过。

- [ ] **Step 4: 跑既有 ChatView UI smoke 不退化**

Run: `$UITEST -only-testing:EchoIMUITests/ChatSmokeTests $UITEST -only-testing:EchoIMUITests/ImageSendSmokeTests`
Expected: 不变（导航标题从 `navigationTitle` 改成 `toolbar(.principal)`，可能影响断言"页面标题包含 peer name"——如果有这种断言，把 query 改成 `chatPrincipalTitle`）。

- [ ] **Step 5: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatView.swift \
         ios-app/EchoIM/Features/Conversations/ConversationsListView.swift \
         ios-app/EchoIM/Features/Contacts/ContactsView.swift
git commit -m "feat(ios): show presence dot and typing indicator on ChatView header"
```

---

## Task 10: PresenceTypingSmokeTests — XCUITest 真实冒烟

**Files:**
- Create: `ios-app/EchoIMUITests/PresenceTypingSmokeTests.swift`

设计依据：§8 P6 + §9 测试策略。XCUITest 不能驱动两个真实账号互发，但可以**真实**验证：
- ChatView 顶部 principal 区域 accessibility identifier 正常存在（之前是 `.navigationTitle`，Task 9 改成了 `.toolbar(.principal)`）
- 在 `chatInput` 输入文字时，本端 `chatPeerTyping` 不出现（典型坑：误把"我在输入"渲染成"对方在输入"）

复用 `ChatSmokeTests` 的登入 → 进会话路径（同 fixture 账号 `smoke@test.local` / `password123`）；不调度第二个账号，所以"对方在线圆点 / 对方 typing"这两条回路只能在 §12 手工验证里靠双模拟器跑。

- [ ] **Step 1: 写 smoke**

```swift
// ios-app/EchoIMUITests/PresenceTypingSmokeTests.swift
import XCTest

final class PresenceTypingSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testChatHeaderShowsPrincipalTitleIdentifier() throws {
        let app = launchAndEnterFirstConversation()

        // Task 9 把 .navigationTitle 改成 .toolbar(.principal) 后，
        // 顶部应当能查到自定义的 chatPrincipalTitle 元素。
        let principal = app.otherElements["chatPrincipalTitle"]
        XCTAssertTrue(
            principal.waitForExistence(timeout: 5),
            "ChatView principal title 自定义视图应存在"
        )

        // 进入瞬间没有"对方正在输入"——除非 fixture 数据里对方真的在打字。
        XCTAssertFalse(
            app.staticTexts["chatPeerTyping"].exists,
            "刚进入会话不应显示 chatPeerTyping"
        )
    }

    @MainActor
    func testOwnInputDoesNotRenderPeerTyping() throws {
        let app = launchAndEnterFirstConversation()

        let input = app.descendants(matching: .any)["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("hi")

        // 本端打字不应在自己屏幕上渲染 chatPeerTyping
        // （这是 vm.peerIsTyping 通过 typingStore 读对方状态的契约）
        XCTAssertFalse(
            app.staticTexts["chatPeerTyping"].exists,
            "本端打字不应触发 chatPeerTyping 渲染"
        )
    }

    // MARK: - Helpers

    /// 复制 ChatSmokeTests 的登入 → 选第一行会话路径。fixture 账号需提前在测试服务端建好。
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

> 如果 `chatPrincipalTitle` 在某些 OS 版本下被 NavigationBar 系统化收敛、`otherElements` 查不到，把 `app.otherElements["chatPrincipalTitle"]` 改成 `app.descendants(matching: .any)["chatPrincipalTitle"]` 兜底。Task 9 中已用 `.accessibilityElement(children: .contain) + .accessibilityIdentifier(...)` 保证元素被暴露。

- [ ] **Step 2: 编译 + 运行**

Run: `$UITEST -only-testing:EchoIMUITests/PresenceTypingSmokeTests`
Expected: 2 个测试通过。前提是测试服务端有 `smoke@test.local` 账号 + 至少一条会话（与现有 `ChatSmokeTests` 同 fixture）。

- [ ] **Step 3: 提交**

```bash
git add ios-app/EchoIMUITests/PresenceTypingSmokeTests.swift
git commit -m "test(ios): UI smoke for presence and typing identifiers"
```

---

## Task 11: 全量 build / test / lint 收尾

**Files:**
- 无新增

- [ ] **Step 1: 全量 build**

Run: `$BUILD`
Expected: 通过；warning 总数与 P5 末态相比无新增（第三方包内部 warning 不计）。

- [ ] **Step 2: 全量单测**

Run: `$TEST`
Expected: 全部通过。重点 PresenceStoreTests / TypingStoreTests / WebSocketClientTypingFrameTests / UserSessionRoutingTests / ChatViewModelPresenceTests / ChatViewModelTypingTests 全过。

- [ ] **Step 3: 全量 UITest**

Run: `$UITEST`
Expected: 全部通过；Task 10 的 PresenceTypingSmokeTests 也应通过（fixture 账号 `smoke@test.local` 必须在测试服务端建好且至少有一条会话——与现有 ChatSmokeTests 共用前置）。

- [ ] **Step 4: 服务端测试不动也得跑一遍兜底**

```bash
npm test --prefix server -- ws messages
```

Expected: 通过。

- [ ] **Step 5: 提交（如果有遗留 lint 修正）**

如果 `$BUILD` 输出 warning 与 P5 末态对比有新增——修掉再提交：

```bash
git add ios-app/EchoIM/...
git commit -m "fix(ios): clean P6 warnings"
```

如果无遗留，跳过该 step。

---

## 手工验证清单（Task 11 之后跑一遍真实双账号场景）

### 12.1 Presence — 单设备登入登出对方端可见

- [ ] 模拟器 A 登录 Alice（已与 Bob 互为好友）
- [ ] 模拟器 B 登录 Bob → 联系人 tab 看到 Alice 行右下角绿点
- [ ] 模拟器 B 进入 Alice 会话 → 顶部 principal 区域 Alice 名字右侧显示绿点
- [ ] 模拟器 A 退出后台 5 秒（observe Alice 离线）→ 模拟器 B 上 Alice 行的绿点消失，会话页顶部绿点消失
- [ ] 模拟器 A 切回前台（重连） → connection.ready 后 PresenceStore.clearAll() → 立即收到 B 的 presence.online → 模拟器 A 上 Bob 行的绿点恢复

### 12.2 Typing — 双向

- [ ] 模拟器 A 在 ChatView 输入框打 "hello"（不发送）
- [ ] 模拟器 B 顶部立即显示"正在输入..."
- [ ] 模拟器 A 停止输入 3 秒 → 模拟器 B 顶部"正在输入..."消失
- [ ] 模拟器 A 再次打字 → 模拟器 B 再次显示
- [ ] 模拟器 A 按发送按钮 → 模拟器 B 立即（不等 3 秒兜底）"正在输入..."消失
- [ ] 模拟器 A 输入再切走 ChatView（返回会话列表）→ 模拟器 B 立即"正在输入..."消失（onDisappear 触发 stopTyping）

### 12.3 Typing 安全定时器兜底

- [ ] 用 Charles / mitmproxy 拦截模拟器 A 的 WS 上行 → 让 typing.stop 帧丢失
- [ ] 模拟器 A 输入"x" 后停 5 秒（idle 3 秒 → 客户端按理已发 stop，但被代理拦掉）
- [ ] 模拟器 B 顶部"正在输入..."应在 5 秒后自动消失（TypingStore 兜底）
- [ ] 关掉代理拦截，恢复 typing 双向能正常工作

### 12.4 重连后 PresenceStore 重建

- [ ] 模拟器 A 与 B、C 三人互为好友，B 在线 / C 离线
- [ ] 模拟器 A 看到 B 绿点、C 灰点
- [ ] 模拟器 A 切飞行模式 5 秒 → 切回 → 重连 connection.ready
- [ ] 重连后立即（< 1 秒）观察：B 绿点回来、C 仍无绿点
- [ ] **关键**：观察 `wsClient` log（如果 P3 加了日志），看到 `clearAll` 在 connection.ready 之后、第一条 presence.online 之前打印

### 12.5 草稿态进入 ChatView

- [ ] 模拟器 A 与 D 是好友但从未发过消息
- [ ] A 联系人列表点 D → 进入草稿态 ChatView
- [ ] 顶部如果 D 在线，依然显示绿点（peer.id 已知，无需 conversationId）
- [ ] 顶部 typing 不显示（草稿态 conversationId == nil → peerIsTyping == false）
- [ ] A 输入文字 → handleTypingInput no-op（conversationId 还没回填，guard let return）→ 服务端不收到 typing
- [ ] A 发送一条消息 → conversationId 回填 → 此后输入再触发 typing 才有效（这是 P5 已知行为）

### 12.6 多账号隔离

- [ ] A 登录 → 看到一组 presence/typing 状态 → 登出
- [ ] B（同设备）登录 → presenceStore / typingStore 应是 fresh 的（UserSession 重建即新 store）
- [ ] 不应残留 A 的好友 id 在 PresenceStore 里

### 12.7 Dark Mode 下圆点对比

- [ ] 切系统 Dark Mode
- [ ] 好友列表 / 会话列表 / 聊天页头部三处绿点都依然清晰可见（白边在 .systemBackground 上自适应）

---

## Self-Review（完成前必过）

- [ ] **P6 覆盖设计 §8 P6 全部要点**：
  - `PresenceStore`（处理 presence.online / .offline，重连 clearAll → 重建） → Task 1 + Task 4
  - 好友列表 / 会话列表 / 聊天页顶部在线圆点 → Task 7 + Task 8 + Task 9
  - `TypingStore` 带 5 秒安全定时器 → Task 2 + Task 4
  - 聊天页顶部"正在输入..." → Task 9
  - 本端 debounce 发 typing.start / typing.stop → Task 3 + Task 6
  - 重连后 PresenceStore 状态与实际在线好友一致 → Task 4（test `wsReadyClearsBeforeSubsequentPresenceOnlineEvents`）

- [ ] **Placeholder 扫描**：

```bash
grep -rn -iE "t[b]d|t[o]do|implement[ -]later|similar[ -]to[ -]task|\\.\\.\\." \
  docs/superpowers/plans/2026-04-27-ios-p6-presence-typing.md \
  | grep -v "^[^:]*:[0-9]*:[[:space:]]*//\?[[:space:]]*\\.\\.\\." \
  | grep -v "现有 .* 不变\|相同模式\|占位\|预演"
```
应只剩 README 风格提示（"// ... 既有实现不变 ..." 这类），不应有未完成代码占位。

- [ ] **类型一致性**（跨任务用到的符号必须自洽）：
  - `PresenceStore` 公开 API：`onlineUserIds: Set<Int>`、`setOnline(_)` / `setOffline(_)` / `isOnline(_)` / `clearAll()` — Task 1 引入；Task 4 / 8 / 9 使用
  - `TypingStore` 公开 API：`typingConversationIds: Set<Int>`、`init(safetyDuration:)` / `handleTypingStart(conversationId:)` / `handleTypingStop(conversationId:)` / `isTyping(_)` — Task 2 引入；Task 4 / 5 使用
  - `WebSocketClient.typingFrameJSON(conversationId:isStart:)` / `sendTyping(conversationId:isStart:)` — Task 3 引入；Task 4 / 8 使用
  - `WebSocketClient._dispatchForTesting(_:)` / `_fireReadyForTesting()`（DEBUG only） — Task 4 Step 2 引入；UserSessionRoutingTests 用
  - `UserSession.presenceStore: PresenceStore` / `typingStore: TypingStore` / `sendTyping(conversationId:isStart:)` — Task 4 引入；Task 8 / 9 使用
  - `ChatViewModel.peerIsTyping: Bool` — Task 5 引入；Task 9 使用
  - `ChatViewModel.handleTypingInput()` / `stopTyping()` / `init(... typingStore: typingSender: idleTypingDuration: ...)` — Task 5 / 6 引入；Task 9 / 测试使用
  - `PresenceDot(size: borderWidth:)` — Task 7 引入；Task 8 / 9 使用
  - `FriendsListView(friends:presenceStore:)` / `ConversationsListView(... presenceStore: typingStore: typingSender: ...)` / `ContactsView(... presenceStore: typingStore: typingSender: ...)` / `ChatView(... presenceStore: typingStore: typingSender: ...)` — Task 8 / 9 引入；MainTabView 调用

- [ ] **不变式 1（store 不订阅 WS，由 UserSession 路由）**：检查 `PresenceStore.swift` / `TypingStore.swift` 都不 import `WebSocketClient`、不持有 wsClient 引用。

- [ ] **不变式 3（clearAll 在 presence.online 之前）**：Task 4 测试 `wsReadyClearsBeforeSubsequentPresenceOnlineEvents` 已断言重连后顺序。

- [ ] **不变式 4（typing.stop 三种触发点）**：
  - idle 3 秒兜底 → Task 6 测试 `idleTimeoutSendsTypingStop`
  - sendText / sendImage 入口 stopTyping → Task 6 Step 3 改造点 4
  - ChatView.onDisappear → Task 9 Step 1 已在 `.onDisappear` 加 `vm.stopTyping()`

- [ ] **不变式 5（typing.start dedupe）**：Task 6 测试 `consecutiveInputsDoNotResendStart`。

- [ ] **不变式 6（TypingStore 安全定时器可重置）**：Task 2 测试 `consecutiveStartsResetSafetyTimer`。

- [ ] **不变式 7（5s > 3s）**：TypingStore 默认 `safetyDuration = 5.0`，ChatViewModel 默认 `idleTypingDuration = 3.0`，常量在 Task 2 / 6 实现里固定。

- [ ] **不变式 8（VM 不重复路由 typing/presence）**：UserSession 是 typingStore / presenceStore 的唯一写入方——Task 4 测试 `UserSessionRoutingTests` 覆盖路由；Task 5 测试 `handleWSEventIgnoresTypingForOtherConversation` 验证 ChatViewModel 对 typing/presence 事件保持 no-op，不重写 store 状态。

- [ ] **服务端契约 0 改动**：

```bash
git diff <P5-tip>..HEAD -- server/
```
应为空。整个 P6 不应该有任何 server/ 下的改动。

- [ ] **`ChatView.init` 多了 presenceStore / typingStore / typingSender → 三个调用方都更新**（Task 8 Step 4 + Task 9 Step 2）：

```bash
grep -rn "ChatView(" ios-app/EchoIM/Features ios-app/EchoIMUITests
```
全部应包含 `presenceStore:` 与 `typingStore:`。

- [ ] **`ChatViewModel.init` 多了 typingStore / typingSender / idleTypingDuration → 测试 mock 同步更新**：

```bash
grep -rn "ChatViewModel(" ios-app/EchoIMTests
```
P5 既有调用如不传新参数，编译应仍能通过（默认值已铺好）；新增的 ChatViewModelTypingTests / ChatViewModelPresenceTests 显式传入。

- [ ] **`FriendsListView` / `ContactsView` / `ConversationsListView` 入参变化 → MainTabView + UI 测试**：

```bash
grep -rn "FriendsListView(\|ContactsView(\|ConversationsListView(" ios-app/EchoIM ios-app/EchoIMTests ios-app/EchoIMUITests
```
所有调用方都应包含 `presenceStore:` 参数。

- [ ] **Lint**：（与 P1-P5 一致）
  - 服务端：未改，无需跑
  - iOS：`$BUILD` warning 为零（项目代码部分）
  - 检查：`xcodebuild ... build 2>&1 | grep -i 'warning'`，应只有第三方包内部 warning

- [ ] **工作目录一致**：所有路径以 `ios-app/EchoIM/...` 开头，无裸相对路径。

---

## 未来阶段的依赖锚点（给 P7+ 计划起草人）

**P7（Profile 编辑 + 头像上传）会触及本阶段的文件**：
- `AvatarView` API 不变；P6 是在调用方包了一层 `ZStack { AvatarView ... PresenceDot }`。如果 P7 想给"自己头像"也复用 AvatarView，注意 PresenceDot 永远不应该叠在自己身上（自己永远在线，没有 UI 价值）——只在 friend / peer 视图叠加。
- `UserSession` P6 增加了 `presenceStore` / `typingStore` 两个公共属性 + `sendTyping(...)`。P7 不需要触碰它们。
- `Features/Shared/Stores/` 目录已经建立——P7 如果有新的全局 `@Observable`（例如 ProfileSyncStore 用于 me 信息变更），应放同一目录。

**P8（打磨 + 测试 + Dark Mode）会触及本阶段的文件**：
- `PresenceDot` 在 Dark Mode 下的边框白色对比需要确认（Dark Mode 下 .systemBackground 是黑色，绿色圆点 + 黑边能看清——但和"我们想要的视觉"对不对要 review，可能要用 `.background` 的反色）
- `ChatView` toolbar.principal 区在长 displayName 时的截断（设计上 `.lineLimit(1)` 已加，截断方式用默认 tail）
- `TypingStore` / `PresenceStore` 的 `@MainActor` 隔离正确性——P8 用 Instruments concurrency profile 验证一遍
- Web 端有 `usePresenceStore` 在登出 / 切账号时的清理逻辑——iOS 这边由 `UserSession` 整体替换天然解决，不需要再加 clear；P8 review 时验证下没有内存泄漏

**P6 引入的设计债**：
- **Typing 渲染没有动画**：当前"正在输入..."是 plain text 出现/消失。Web 端用三点闪烁动画。P8 可考虑加 `.symbolEffect(.pulse)` 或 dot 动画。
- **PresenceDot 位置硬编码 offset(2, 2)**：在 40 / 44 头像上看着合适，但 P7 头像编辑页可能用不同尺寸；P7 起草时把 offset 暴露成参数 / 改成基于 size 的相对位置。
- **TypingStore 没有"用户级"维度**：当前只用 conversationId 索引；改群聊时需要扩成 `[ConversationId: Set<UserId>]`。P6 文件结构允许这种扩展（store 是单一职责类，加字段不影响 API 契约）。
- **没有覆盖"presence 事件早于 connection.ready 到达"的边界**：理论上不可能（服务端 `ws.ts:313` 是先 send connection.ready 再 sendPresenceSnapshot），但客户端代码不会 reject 这种顺序——会照常 setOnline。P8 添加 Sentry-like 日志后可以记一次"序乱"事件，便于发现服务端 bug。
