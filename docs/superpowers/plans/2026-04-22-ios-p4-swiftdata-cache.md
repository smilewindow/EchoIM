# iOS P4 实施计划：本地持久化（SwiftData 缓存）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ios-app/` 从 P3 的"文字消息 + 实时 WS（完全依赖网络，进页面要等一次 `GET /messages`）"推进到"杀 App 再进秒开、断网仍能滑历史、消息列表先读本地缓存即刻渲染，然后再和服务端做增量对齐"——对应设计文档第 8 节的 P4 + §11.1 的服务端契约小调整。

**Architecture:** 三件事并行展开：
1. **服务端** 给 `GET /api/conversations/:id/messages` 加 `?limit=` 参数（设计 §11.1），让客户端"本地命中 N 条、只向服务端要 `(50-N)` 条"的补缺策略成立。
2. **客户端 SwiftData 层**：`CachedMessage` / `ConversationMeta` 两个 `@Model`，分别封装在 `MessageStore` / `ConversationMetaStore` 两个 `@ModelActor` 里；`@Model` 严禁跨 actor，store 出口统一返回 Sendable 的 `Message` / `ConversationMetaSnapshot`（设计 §5.2）。
3. **容器重构**：把 WS 客户端 / 按 userId 的 `ModelContainer` / 需要会话上下文的 repository 收到新类型 `UserSession`；`AppContainer` 退化成"登录态无关的资源 + 当前 session"。`tearDownSession` 扩展为三阶段（Nuke 清 → `session = nil` → 删 `applicationSupport/EchoIM/users/<id>/` 目录，设计 §2.2、§5.5）。

`ChatViewModel` / `ConversationsListViewModel` 改造为"先读本地缓存即刻渲染 → 再异步增量补齐"。`refetchMissedMessages` 升级为循环翻页 + 20 页安全阀（设计 §5.3 场景 C）。`loadOlder` 变成"本地优先 + 远端补缺"（设计 §5.3 上滑段）。Me 页增加"清除聊天缓存"按钮（设计 §5.4）。

**Tech Stack:** SwiftUI、Swift Concurrency、**SwiftData**（`@Model`、`@ModelActor`、`ModelConfiguration`、`ModelContainer`）、Swift Testing、XCUITest、Vitest（服务端）。

**TDD 适用范围（与 P1/P2/P3 一致）：**
- **纯逻辑 → TDD**：服务端 `?limit=` querystring 校验与 SQL；`MessageStore` / `ConversationMetaStore` 的 CRUD + 连续后缀不变式；`ChatViewModel` 的场景 A/B/C 状态机与 `loadOlder` 本地优先；`ConversationsListViewModel` 的 meta-first 渲染。
- **View / Session 生命周期 → 编译 + 模拟器手工清单**：`MainTabView` 接入 `UserSession` 后的登录 / 登出 / 冷启动流转；`tearDownSession` 三阶段的真实 SwiftData 文件落盘 / 清理由手工清单验证；`MeView` 的"清除聊天缓存"按钮走 XCUITest smoke + 手工。

**服务端契约改动：** 仅一处，见 Task 1。Web 客户端不传 `limit`，服务端 default 50，行为不变；向后兼容。

**不在 P4 范围（明确延后）：**
- **图片消息 + `ImageSendStage` 阶段化重试** → P5；P4 只确保 `LocalMessage.localImageData` 字段保留、`CachedMessage.mediaUrl` 存得下、`ChatsList` 预览已经在 P3 展示 `[图片]`。
- **Presence + Typing 的 UI 响应** → P6；`PresenceStore.clearAll()` 和"循环 online 重建"等 `connection.ready` 之后的 step 5 仍延后。
- **`friend_request.*` 增量处理** → P6；P4 重连时仍靠 ContactsView `.refreshable`。
- **Profile 编辑 + 头像上传** → P7。
- **SwiftData schema migration**：P4 是第一次建表，没有旧 schema；以后加字段时再引入 `VersionedSchema` + `SchemaMigrationPlan`。P4 目标文件 `cache.sqlite` 直接用 `Schema([CachedMessage.self, ConversationMeta.self])`，冷启动发现 schema 对不上（极端场景：开发中手动改了 `@Model`）→ 删库重建，不做迁移（走 `ModelContainer` 初始化抛错的 fallback 分支）。
- **`ChatViewModel.reconcileAfterReconnect` 的草稿 promote 优化**：P3 已经实现（`handleWSReady` 草稿态分支），P4 只替换其"promote 后拉最新"里的单次补拉 → Task 11 的循环翻页版本；逻辑不动。
- **加密 / 本地消息全文索引** → 已知限制，作品集范围不做。

**已知妥协：**
- **SwiftData 写入是 best-effort**：`MessageStore.append([...])` / `ConversationMetaStore.upsert(...)` 失败（磁盘满、SQLite 损坏）不会回滚 UI；`load` / `refetch` / `loadOlder` 路径会 `try? await` 等一次写入，WS / send confirmed 路径用 `Task { ... }` fire-and-forget，下一次 `load()` 命中会再写。
- **20 页安全阀触顶**：冷启动 / 长时间离线后 `refetchMissedMessages` 累计翻到 1000 条仍未到尾（= 错过 ≥ 1001 条新消息）→ 停止补拉；下一次 `connection.ready` / 重新进入聊天页会从新的 `newestCachedMessageId` 继续向后追。用户上滑只负责更老历史（Task 12），不能追回安全阀后剩余的新消息。
- **`ConversationMeta` 的 `unread_count`**：meta-first 渲染用的是本地缓存值；服务端真实值由后续 `refresh()` 覆盖。这意味着"短暂看到过时未读数"是预期行为（设计 §5.3 冷启动场景）。
- **清除聊天缓存不触发登出**：仅清 SwiftData + Nuke，保留 token + 当前 session 的 `wsClient`；清完后 `ChatView` 下一次进入相当于冷启动走场景 A 全量拉。

---

## 开发环境前提

沿用 P1/P2/P3（不重复）。命令约定：

```bash
# 服务端 lint + test
npm run lint --prefix server
npm test --prefix server

# iOS 编译（Debug）
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5,arch=arm64' \
  -configuration Debug build

# iOS 单测
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5,arch=arm64' \
  test -only-testing:EchoIMTests

# iOS UI 测
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5,arch=arm64' \
  test -only-testing:EchoIMUITests
```

记为 `$BUILD` / `$TEST` / `$UITEST`。服务端 lint 记为 `$SLINT`、测试为 `$STEST`。

**SwiftData 单元测试约定**：所有 store 测试都用 in-memory store，避免磁盘文件污染：

```swift
let schema = Schema([CachedMessage.self, ConversationMeta.self])
let config = ModelConfiguration(isStoredInMemoryOnly: true)
let container = try ModelContainer(for: schema, configurations: [config])
```

**后端前提**：联调需要后端在跑（`docker compose up` 或 `npm --prefix server run dev`）。沿用 P3 的两账号 A、B（互为好友）。

---

## 文件结构（新增 / 修改）

新增：
- `ios-app/EchoIM/Core/Storage/Models/CachedMessage.swift` — `@Model` 持久化一条消息（对齐 `Message` 字段；`clientTempId` 不落盘）
- `ios-app/EchoIM/Core/Storage/Models/ConversationMeta.swift` — `@Model` 每会话缓存元数据（`oldest`/`newest`/`lastRead`/`unreadCount` + 最后消息预览字段）
- `ios-app/EchoIM/Core/Storage/Models/ConversationMetaSnapshot.swift` — Sendable plain struct，`ConversationMeta.snapshot()` 出 actor 用
- `ios-app/EchoIM/Core/Storage/MessageStore.swift` — `@ModelActor`，封装 `append` / `loadOlder` / `loadLatest` / `deleteAll`，返回 `[Message]`
- `ios-app/EchoIM/Core/Storage/ConversationMetaStore.swift` — `@ModelActor`，封装 `upsert` / `load` / `loadAll` / `deleteAll`，返回 `ConversationMetaSnapshot?`
- `ios-app/EchoIM/App/UserSession.swift` — `@MainActor`，持 `userId` / `modelContainer` / `wsClient` / 会话相关 repository 工厂（`messageRepo` / `conversationRepo`），以及 `messageStore()` / `conversationMetaStore()` 工厂
- `ios-app/EchoIMTests/MessageStoreTests.swift` — 4 用例（append 去重、loadLatest DESC、loadOlder cursor、deleteAll）
- `ios-app/EchoIMTests/ConversationMetaStoreTests.swift` — 3 用例（upsert 新建 / 覆盖、loadAll 排序、deleteAll）
- `ios-app/EchoIMTests/ChatViewModelCacheTests.swift` — 5 用例（场景 A 冷启、场景 B append、loadOlder 本地命中、loadOlder 本地不够补远端、refetch 循环翻页）
- `ios-app/EchoIMTests/ConversationsListViewModelCacheTests.swift` — 2 用例（meta-first 立即渲染、refresh 覆盖）
- `ios-app/EchoIMTests/UserSessionTests.swift` — 2 用例（bootstrap 建目录 + excludeFromBackup、tearDown 释放 container）
- `ios-app/EchoIMUITests/ClearCacheSmokeTests.swift` — 1 用例（Me 页点击按钮 → 确认弹窗 → 再进 Chats tab 会话列表不崩）

修改：
- `server/src/routes/conversations.ts` — `GET /:id/messages` querystring schema 加 `limit`，SQL `LIMIT $3` 参数化
- `server/tests/messages.test.ts` — 新增 3 个 `?limit=` 用例（合法 / 越界 / 与 before+after 组合）
- `ios-app/EchoIM/Features/Chat/MessageRepository.swift` — `list(...)` 新增 `limit: Int?` 入参，走 querystring
- `ios-app/EchoIM/Features/Chat/ChatViewModel.swift` — 注入可选 `MessageStore` / `ConversationMetaStore`；`load` 改为场景 A / B；`loadOlder` 本地优先；`refetchMissedMessages` 改循环翻页 + 20 页安全阀；write-through 到 store
- `ios-app/EchoIM/Features/Chat/ChatView.swift` — `ChatView` 初始化新增两个 store 参数（转发给 `ChatViewModel`）
- `ios-app/EchoIM/Features/Conversations/ConversationsListViewModel.swift` — `load()` 先 `loadAll()` 拿 snapshots 渲染，再调 `refresh()`
- `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift` — 从 `UserSession` 取 `ConversationMetaStore`、转发
- `ios-app/EchoIM/App/AppContainer.swift` — 搬出 `wsClient` / `makeConversationRepository` / `makeMessageRepository`；新增 `session: UserSession?`；`bootstrap` 与 `handleLoginSuccess` 触发 `bootstrapSession(userId:)`；`tearDownSession` 改三阶段；新增 `clearChatCache()` 方法
- `ios-app/EchoIM/App/RootView.swift` — 如果需要让 scenePhase 联动作用于 `session?.wsClient` 而不是 `container.wsClient`
- `ios-app/EchoIM/Features/Main/MainTabView.swift` — 所有取 wsClient / repository 的点改从 `container.session?` 取；`currentUserId` 从 session 拿
- `ios-app/EchoIM/Features/Contacts/ContactsView.swift` — 同步上游 wsClient 取点（`ContactsView` 已接收 wsClient 作为参数，只需在 `MainTabView` 调用处改）
- `ios-app/EchoIM/Features/Me/MeView.swift` — 新增"清除聊天缓存"按钮 + 确认弹窗 + 调 `container.clearChatCache()`
- `ios-app/EchoIMTests/AppContainerTests.swift` — 扩展 teardown 测试到三阶段（Nuke + session nil + 目录删除）
- `ios-app/EchoIMTests/AppContainerRefreshTests.swift` — 若 API 变动同步改
- `ios-app/EchoIMTests/ChatViewModelLoadTests.swift` / `ChatViewModelWSTests.swift` / `ChatViewModelSendTests.swift` / `ChatViewModelReadTests.swift` — 所有 `ChatViewModel(...)` 构造处 store 参数传 `nil`（P3 测试行为不变）
- `ios-app/EchoIMTests/MessageRepositoryTests.swift` — 新增 1 用例（带 limit 的 URL 拼装）
- `ios-app/EchoIMTests/ConversationsListViewModelTests.swift` — 所有构造处加 `metaStore: nil`（P3 测试行为不变）
- `ios-app/README.md` — Status 加 "P4 done: SwiftData cache (scenario A/B/C 连续后缀不变式) + UserSession + Me 清缓存"

---

## 任务分解

共 14 个 task。顺序：服务端契约 → 客户端基础设施（模型 + store + session）→ 容器接线 → ChatViewModel 重写 → ConversationsListViewModel → UI → 收尾。

---

### Task 1：服务端 `GET /api/conversations/:id/messages` 加 `?limit=` 参数

**Files:**
- Modify: `server/src/routes/conversations.ts:36-88`
- Modify: `server/tests/messages.test.ts:390-513`（`describe('GET /api/conversations/:id/messages')` block 内）

- [ ] **Step 1：先写失败的测试**

在 `server/tests/messages.test.ts` 的 `describe('GET /api/conversations/:id/messages', () => { ... })` block 里追加三个 case（放在 `returns 401 when unauthenticated` 之后）：

```typescript
it('limits results when ?limit=N is provided', async () => {
  const { alice, bob } = await setupFriends(app)
  const r1 = await sendMessage(app, alice.token, bob.user.id, 'First')
  const convId = r1.json().conversation_id
  await sendMessage(app, alice.token, bob.user.id, 'Second')
  await sendMessage(app, alice.token, bob.user.id, 'Third')

  const res = await app.inject({
    method: 'GET',
    url: `/api/conversations/${convId}/messages?limit=2`,
    headers: { authorization: `Bearer ${alice.token}` },
  })
  expect(res.statusCode).toBe(200)
  const msgs = res.json<Array<{ body: string }>>()
  expect(msgs).toHaveLength(2)
  expect(msgs[0].body).toBe('Third')  // 默认 DESC：最新在前
  expect(msgs[1].body).toBe('Second')
})

it('rejects ?limit=0 and ?limit=51 with 400', async () => {
  const { alice, bob } = await setupFriends(app)
  const r1 = await sendMessage(app, alice.token, bob.user.id, 'First')
  const convId = r1.json().conversation_id

  const tooLow = await app.inject({
    method: 'GET',
    url: `/api/conversations/${convId}/messages?limit=0`,
    headers: { authorization: `Bearer ${alice.token}` },
  })
  expect(tooLow.statusCode).toBe(400)

  const tooHigh = await app.inject({
    method: 'GET',
    url: `/api/conversations/${convId}/messages?limit=51`,
    headers: { authorization: `Bearer ${alice.token}` },
  })
  expect(tooHigh.statusCode).toBe(400)
})

it('combines ?after= with ?limit= (ASC order, capped)', async () => {
  const { alice, bob } = await setupFriends(app)
  const r1 = await sendMessage(app, alice.token, bob.user.id, 'First')
  const firstId = r1.json().id
  const convId = r1.json().conversation_id
  await sendMessage(app, alice.token, bob.user.id, 'Second')
  await sendMessage(app, alice.token, bob.user.id, 'Third')

  const res = await app.inject({
    method: 'GET',
    url: `/api/conversations/${convId}/messages?after=${firstId}&limit=1`,
    headers: { authorization: `Bearer ${alice.token}` },
  })
  expect(res.statusCode).toBe(200)
  const msgs = res.json<Array<{ body: string }>>()
  expect(msgs).toHaveLength(1)
  expect(msgs[0].body).toBe('Second')  // ASC，最小 id 先
})
```

- [ ] **Step 2：跑失败的测试**

```bash
$STEST -- messages.test.ts
```

预期：3 个新 case 都 FAIL（`limit=0` / `limit=51` 现在会被视为"未知参数"→ `additionalProperties: false` 拒绝返回 400，所以 `rejects` 那条可能意外通过；`limits results` 和 `combines after+limit` 会因为 `additionalProperties: false` 返回 400 而失败）。

> **如果 `rejects ?limit=0` 意外通过**也没关系，下一步实现里仍然要把它纳入 schema；实现之后它测的是 "schema 明确 minimum=1 的拒绝"，语义更强。

- [ ] **Step 3：改 querystring schema 和 SQL**

编辑 `server/src/routes/conversations.ts`，把 `GET /:id/messages` 的 handler 和 schema 改成：

```typescript
fastify.get('/:id/messages', {
  schema: {
    querystring: {
      type: 'object',
      properties: {
        before: { type: 'integer', minimum: 1 },
        after: { type: 'integer', minimum: 1 },
        limit: { type: 'integer', minimum: 1, maximum: 50, default: 50 },
      },
      additionalProperties: false,
    },
  },
}, async (request, reply) => {
  const { id } = request.params as { id: string }
  const { before, after, limit } = request.query as { before?: number; after?: number; limit: number }
  const userId = request.user.id

  if (!/^\d+$/.test(id)) {
    return reply.status(400).send({ error: 'Invalid id' })
  }
  if (before !== undefined && after !== undefined) {
    return reply.status(400).send({ error: 'Cannot use both before and after' })
  }
  const convId = Number(id)

  const memberCheck = await fastify.pool.query(
    'SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
    [convId, userId]
  )
  if (memberCheck.rowCount === 0) {
    return reply.status(404).send({ error: 'Not a member of this conversation' })
  }

  let result
  if (before) {
    result = await fastify.pool.query(
      'SELECT * FROM messages WHERE conversation_id = $1 AND id < $2 ORDER BY id DESC LIMIT $3',
      [convId, before, limit]
    )
  } else if (after) {
    result = await fastify.pool.query(
      'SELECT * FROM messages WHERE conversation_id = $1 AND id > $2 ORDER BY id ASC LIMIT $3',
      [convId, after, limit]
    )
  } else {
    result = await fastify.pool.query(
      'SELECT * FROM messages WHERE conversation_id = $1 ORDER BY id DESC LIMIT $2',
      [convId, limit]
    )
  }

  return reply.status(200).send(result.rows)
})
```

- [ ] **Step 4：跑测试**

```bash
$STEST -- messages.test.ts
```

预期：`describe('GET /api/conversations/:id/messages')` 下全部 6 条原有 + 3 条新增共 9 条全绿。

- [ ] **Step 5：lint + 提交**

```bash
$SLINT
git add server/src/routes/conversations.ts server/tests/messages.test.ts
git commit -m "feat(server): add ?limit= query param to GET conversations messages"
```

---

### Task 2：`MessageRepository` 支持 `limit` 参数

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/MessageRepository.swift:9-59`
- Modify: `ios-app/EchoIMTests/MessageRepositoryTests.swift`

- [ ] **Step 1：先写失败的测试**

在 `ios-app/EchoIMTests/MessageRepositoryTests.swift` 末尾（最后一个 `}` 前，最后一个测试方法之后）追加一个新用例，校验 URL 拼装时 `limit` 正确放入 querystring：

```swift
@Test
func listAppendsLimitQueryParam() async throws {
    let api = APIClient(session: MockURLProtocol.makeSession())
    let repo = MessageRepositoryImpl(api: api)

    MockURLProtocol.stub { request in
        let url = request.url!
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        let queries = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(queries["after"] == "10")
        #expect(queries["limit"] == "25")
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("[]".utf8))
    }

    _ = try await repo.list(conversationId: 1, cursor: .after(10), limit: 25, token: "t")
}
```

（如果 `MessageRepositoryTests` 里已有一个 `@Test func listBuildsCorrectURL` 之类的基础用例，参考它的 stub 风格追加本用例；`MockURLProtocol.stub` 与 `MockURLProtocol.makeSession()` 的 API 以 `ios-app/EchoIMTests/MockURLProtocol.swift` 里现有实现为准。）

- [ ] **Step 2：跑失败的测试**

```bash
$TEST -only-testing:EchoIMTests/MessageRepositoryTests
```

预期：编译失败——`list(conversationId:cursor:limit:token:)` 签名不存在。

- [ ] **Step 3：给协议 + impl 加 `limit` 参数**

编辑 `ios-app/EchoIM/Features/Chat/MessageRepository.swift`：

```swift
protocol MessageRepository {
    /// 无 cursor → 最新 limit 条（DESC）
    /// .before → 更早 limit 条（DESC）
    /// .after → 更新 limit 条（ASC）
    /// `limit == nil` 走服务端默认（50）；上限 50（由服务端 schema 强约束）。
    func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message]
    func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message
    func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws
}

@MainActor
final class MessageRepositoryImpl: MessageRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] {
        var comps = URLComponents()
        comps.path = Endpoints.Conversations.messages(conversationId: conversationId)
        var items: [URLQueryItem] = []
        switch cursor {
        case .before(let id):
            items.append(URLQueryItem(name: "before", value: String(id)))
        case .after(let id):
            items.append(URLQueryItem(name: "after", value: String(id)))
        case nil:
            break
        }
        if let limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if !items.isEmpty {
            comps.queryItems = items
        }
        let path = comps.path + (comps.percentEncodedQuery.map { "?" + $0 } ?? "")
        return try await api.request(path, token: token)
    }

    // sendText / markRead 不变
}
```

- [ ] **Step 4：修所有 `list(conversationId:cursor:token:)` 调用处加 `limit:`**

`ChatViewModel.swift` 里三处调用（`load`、`loadOlder`、`refetchMissedMessages`）先临时传 `limit: nil`——等 Task 11/12 再把 limit 真正用起来。这一步只保持编译通过：

```swift
let rows = try await messageRepo.list(
    conversationId: conversationId,
    cursor: nil,
    limit: nil,
    token: token
)
```

（三处都改。）

所有旧测试（`ChatViewModelLoadTests` / `ChatViewModelWSTests` / `ChatViewModelSendTests` / `ChatViewModelReadTests` / `MessageRepositoryTests` 现有用例）里如果 mock 了 `list` 方法，签名也要对齐。

搜一下：

```bash
grep -rn "list(conversationId:" ios-app/EchoIM ios-app/EchoIMTests | grep -v ".build/"
```

把 mock 实现（例如 `class MockMessageRepository: MessageRepository { ... func list(...) }`）都加上 `limit: Int?` 参数；mock 内部可以忽略。

- [ ] **Step 5：跑所有 iOS 单测**

```bash
$TEST
```

预期：新 case 通过；所有 P3 遗留测试通过（因为 mock 签名和真实签名都对齐了）。

- [ ] **Step 6：提交**

```bash
git add ios-app/EchoIM/Features/Chat/MessageRepository.swift \
        ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
        ios-app/EchoIMTests/MessageRepositoryTests.swift \
        $(grep -rln "class Mock.*MessageRepository" ios-app/EchoIMTests)
git commit -m "feat(ios): thread limit parameter through MessageRepository.list"
```

---

### Task 3：SwiftData 模型 `CachedMessage` / `ConversationMeta` + `ConversationMetaSnapshot`

**Files:**
- Create: `ios-app/EchoIM/Core/Storage/Models/CachedMessage.swift`
- Create: `ios-app/EchoIM/Core/Storage/Models/ConversationMeta.swift`
- Create: `ios-app/EchoIM/Core/Storage/Models/ConversationMetaSnapshot.swift`

本任务只引入"死代码"——模型 + Sendable snapshot + 单向映射（`CachedMessage.asMessage()` / `ConversationMeta.snapshot()`），还没人用它们。Store 在 Task 4 / 5 包上。

- [ ] **Step 1：创建 `CachedMessage.swift`**

内容：

```swift
import Foundation
import SwiftData

/// 落盘的消息实体。对齐 API `Message` 的所有字段（`clientTempId` 不存——发送者本地
/// merge 用，对"再进 App 看到这条消息"毫无用处）。只能在 `MessageStore` 这个 @ModelActor
/// 内部使用；出 actor 边界统一 `asMessage()` 映射为 Sendable `Message`（设计 §5.2）。
@Model
final class CachedMessage {
    @Attribute(.unique) var id: Int
    var conversationId: Int
    var senderId: Int
    var body: String?
    var messageType: String
    var mediaUrl: String?
    var createdAt: Date

    init(
        id: Int,
        conversationId: Int,
        senderId: Int,
        body: String?,
        messageType: String,
        mediaUrl: String?,
        createdAt: Date
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.body = body
        self.messageType = messageType
        self.mediaUrl = mediaUrl
        self.createdAt = createdAt
    }

    /// 出 actor 边界时用。@Model 不是 Sendable，绝不能直接返回给 VM。
    func asMessage() -> Message {
        Message(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            body: body,
            messageType: messageType,
            mediaUrl: mediaUrl,
            createdAt: createdAt,
            clientTempId: nil
        )
    }
}
```

- [ ] **Step 2：创建 `ConversationMeta.swift`**

内容：

```swift
import Foundation
import SwiftData

/// 每会话一条的元数据，维护连续后缀不变式所需的边界游标 + 会话列表预览字段。
/// 仅在 `ConversationMetaStore` 内部使用；出口用 `ConversationMetaSnapshot`。
@Model
final class ConversationMeta {
    @Attribute(.unique) var conversationId: Int

    /// 本地缓存中最旧一条消息的 id；`nil` = 缓存为空（还没做过场景 A 拉取）。
    var oldestCachedMessageId: Int?
    /// 本地缓存中最新一条消息的 id；`nil` = 缓存为空。
    var newestCachedMessageId: Int?
    /// 本地已记录的已读上限。服务端推 `conversation.updated` 或本地 markRead 后推进。
    var lastReadMessageId: Int?
    /// 未读数。冷启动展示用；服务端 `GET /api/conversations` 的真实值会覆盖。
    var unreadCount: Int

    // 会话列表预览字段（冷启动时立即渲染，不等网络）。
    var lastMessageBody: String?
    var lastMessageType: String?
    var lastMessageAt: Date?

    // Peer summary：冷启动会话列表要显示好友头像/昵称，不能用占位空字符串。
    var peerUserId: Int
    var peerUsername: String
    var peerDisplayName: String?
    var peerAvatarUrl: String?

    init(
        conversationId: Int,
        peerUserId: Int,
        peerUsername: String,
        peerDisplayName: String? = nil,
        peerAvatarUrl: String? = nil,
        oldestCachedMessageId: Int? = nil,
        newestCachedMessageId: Int? = nil,
        lastReadMessageId: Int? = nil,
        unreadCount: Int = 0,
        lastMessageBody: String? = nil,
        lastMessageType: String? = nil,
        lastMessageAt: Date? = nil
    ) {
        self.conversationId = conversationId
        self.peerUserId = peerUserId
        self.peerUsername = peerUsername
        self.peerDisplayName = peerDisplayName
        self.peerAvatarUrl = peerAvatarUrl
        self.oldestCachedMessageId = oldestCachedMessageId
        self.newestCachedMessageId = newestCachedMessageId
        self.lastReadMessageId = lastReadMessageId
        self.unreadCount = unreadCount
        self.lastMessageBody = lastMessageBody
        self.lastMessageType = lastMessageType
        self.lastMessageAt = lastMessageAt
    }

    func snapshot() -> ConversationMetaSnapshot {
        .init(
            conversationId: conversationId,
            peerUserId: peerUserId,
            peerUsername: peerUsername,
            peerDisplayName: peerDisplayName,
            peerAvatarUrl: peerAvatarUrl,
            oldestCachedMessageId: oldestCachedMessageId,
            newestCachedMessageId: newestCachedMessageId,
            lastReadMessageId: lastReadMessageId,
            unreadCount: unreadCount,
            lastMessageBody: lastMessageBody,
            lastMessageType: lastMessageType,
            lastMessageAt: lastMessageAt
        )
    }
}
```

- [ ] **Step 3：创建 `ConversationMetaSnapshot.swift`**

内容：

```swift
import Foundation

/// `ConversationMeta` 的 Sendable 值类型镜像。ViewModel / Repository 使用这种，
/// 绝不碰 @Model 本体（设计 §5.2）。
struct ConversationMetaSnapshot: Sendable, Equatable {
    let conversationId: Int
    let peerUserId: Int
    let peerUsername: String
    let peerDisplayName: String?
    let peerAvatarUrl: String?
    let oldestCachedMessageId: Int?
    let newestCachedMessageId: Int?
    let lastReadMessageId: Int?
    let unreadCount: Int
    let lastMessageBody: String?
    let lastMessageType: String?
    let lastMessageAt: Date?
}
```

- [ ] **Step 4：编译通过**

```bash
$BUILD
```

预期：编译通过（只是加了新文件）。`Xcode Build Phases` 对新建 Swift 文件会自动纳入 target（iOS 项目默认）；如果走 CLI + project generation 链路，确认 `EchoIM.xcodeproj/project.pbxproj` 里有新文件引用（打开 Xcode 一次让它自动加入，或手工编辑 pbxproj）。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Core/Storage/Models/CachedMessage.swift \
        ios-app/EchoIM/Core/Storage/Models/ConversationMeta.swift \
        ios-app/EchoIM/Core/Storage/Models/ConversationMetaSnapshot.swift \
        ios-app/EchoIM.xcodeproj/project.pbxproj
git commit -m "feat(ios): add CachedMessage / ConversationMeta @Model entities"
```

---

### Task 4：`MessageStore`（`@ModelActor`）

**Files:**
- Create: `ios-app/EchoIM/Core/Storage/MessageStore.swift`
- Create: `ios-app/EchoIMTests/MessageStoreTests.swift`

- [ ] **Step 1：先写 4 个失败的测试**

创建 `ios-app/EchoIMTests/MessageStoreTests.swift`：

```swift
import Testing
import Foundation
import SwiftData
@testable import EchoIM

@Suite
struct MessageStoreTests {
    // MARK: helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CachedMessage.self, ConversationMeta.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeMessage(id: Int, conversationId: Int = 1, senderId: Int = 10, body: String? = nil) -> Message {
        Message(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            body: body ?? "m-\(id)",
            messageType: "text",
            mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + id)),
            clientTempId: nil
        )
    }

    // MARK: tests

    @Test
    func appendIsIdempotentOnDuplicateIds() async throws {
        let container = try makeContainer()
        let store = MessageStore(modelContainer: container)

        let m1 = makeMessage(id: 10)
        let m2 = makeMessage(id: 11)
        try await store.append([m1, m2])
        try await store.append([m1, m2])  // 重复写不应产生重复行

        let latest = try await store.loadLatest(conversationId: 1, limit: 50)
        #expect(latest.count == 2)
        #expect(Set(latest.map(\.id)) == [10, 11])
    }

    @Test
    func loadLatestReturnsNewestFirst() async throws {
        let container = try makeContainer()
        let store = MessageStore(modelContainer: container)

        try await store.append((1...10).map { makeMessage(id: $0) })

        let latest = try await store.loadLatest(conversationId: 1, limit: 3)
        #expect(latest.map(\.id) == [10, 9, 8])
    }

    @Test
    func loadOlderReturnsStrictlyBeforeCursor() async throws {
        let container = try makeContainer()
        let store = MessageStore(modelContainer: container)

        try await store.append((1...10).map { makeMessage(id: $0) })

        let older = try await store.loadOlder(conversationId: 1, before: 5, limit: 10)
        #expect(older.map(\.id) == [4, 3, 2, 1])
    }

    @Test
    func deleteAllPurgesAllConversations() async throws {
        let container = try makeContainer()
        let store = MessageStore(modelContainer: container)

        try await store.append([
            makeMessage(id: 1, conversationId: 1),
            makeMessage(id: 2, conversationId: 2),
        ])

        try await store.deleteAll()
        let c1 = try await store.loadLatest(conversationId: 1, limit: 50)
        let c2 = try await store.loadLatest(conversationId: 2, limit: 50)
        #expect(c1.isEmpty)
        #expect(c2.isEmpty)
    }
}
```

- [ ] **Step 2：跑失败的测试**

```bash
$TEST -only-testing:EchoIMTests/MessageStoreTests
```

预期：编译失败——`MessageStore` 类型不存在。

- [ ] **Step 3：实现 `MessageStore`**

创建 `ios-app/EchoIM/Core/Storage/MessageStore.swift`：

```swift
import Foundation
import SwiftData

/// 消息缓存的持久化入口。所有读写都包在这个 actor 里，@Model 不出 actor 边界。
///
/// 签名约定：入参 Sendable 的 `Message`，出参 `[Message]`。调用方是 ViewModel / Repository，
/// 它们感知不到 `CachedMessage` 的存在（设计 §5.2）。
@ModelActor
actor MessageStore {
    /// 追加一批消息。对重复 id（唯一键）幂等——SwiftData 会在 insert 后 save 时报错，
    /// 这里改用"先 fetch 判重再 insert"的朴素方案（p4 量级不大，百级内够用）。
    func append(_ messages: [Message]) async throws {
        guard !messages.isEmpty else { return }

        let ids = messages.map(\.id)
        var existing = Set<Int>()
        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate<CachedMessage> { ids.contains($0.id) }
        )
        for row in try modelContext.fetch(descriptor) {
            existing.insert(row.id)
        }

        for message in messages where !existing.contains(message.id) {
            let row = CachedMessage(
                id: message.id,
                conversationId: message.conversationId,
                senderId: message.senderId,
                body: message.body,
                messageType: message.messageType,
                mediaUrl: message.mediaUrl,
                createdAt: message.createdAt
            )
            modelContext.insert(row)
        }
        try modelContext.save()
    }

    /// DESC + LIMIT：返回最新 limit 条（最新在前）。
    func loadLatest(conversationId: Int, limit: Int) async throws -> [Message] {
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate<CachedMessage> { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.id, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map { $0.asMessage() }
    }

    /// id < before，DESC，最多 limit 条。用于上滑翻页本地命中。
    func loadOlder(conversationId: Int, before: Int, limit: Int) async throws -> [Message] {
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate<CachedMessage> {
                $0.conversationId == conversationId && $0.id < before
            },
            sortBy: [SortDescriptor(\.id, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map { $0.asMessage() }
    }

    /// 清空所有会话所有消息（Me 页"清除聊天缓存"用）。
    func deleteAll() async throws {
        try modelContext.delete(model: CachedMessage.self)
        try modelContext.save()
    }
}
```

- [ ] **Step 4：跑测试**

```bash
$TEST -only-testing:EchoIMTests/MessageStoreTests
```

预期：4 个 case 全绿。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Core/Storage/MessageStore.swift \
        ios-app/EchoIMTests/MessageStoreTests.swift \
        ios-app/EchoIM.xcodeproj/project.pbxproj
git commit -m "feat(ios): add MessageStore @ModelActor with append/loadLatest/loadOlder"
```

---

### Task 5：`ConversationMetaStore`（`@ModelActor`）

**Files:**
- Create: `ios-app/EchoIM/Core/Storage/ConversationMetaStore.swift`
- Create: `ios-app/EchoIMTests/ConversationMetaStoreTests.swift`

- [ ] **Step 1：先写 3 个失败的测试**

创建 `ios-app/EchoIMTests/ConversationMetaStoreTests.swift`：

```swift
import Testing
import Foundation
import SwiftData
@testable import EchoIM

@Suite
struct ConversationMetaStoreTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CachedMessage.self, ConversationMeta.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// 测试用 snapshot helper：peer 字段给默认值，本 suite 关心的是 oldest/newest/unread 等。
    private func snap(
        conversationId: Int,
        peerUserId: Int = 999,
        peerUsername: String? = nil,
        peerDisplayName: String? = nil,
        peerAvatarUrl: String? = nil,
        oldestCachedMessageId: Int? = nil,
        newestCachedMessageId: Int? = nil,
        lastReadMessageId: Int? = nil,
        unreadCount: Int = 0,
        lastMessageBody: String? = nil,
        lastMessageType: String? = nil,
        lastMessageAt: Date? = nil
    ) -> ConversationMetaSnapshot {
        ConversationMetaSnapshot(
            conversationId: conversationId,
            peerUserId: peerUserId,
            peerUsername: peerUsername ?? "peer\(conversationId)",
            peerDisplayName: peerDisplayName,
            peerAvatarUrl: peerAvatarUrl,
            oldestCachedMessageId: oldestCachedMessageId,
            newestCachedMessageId: newestCachedMessageId,
            lastReadMessageId: lastReadMessageId,
            unreadCount: unreadCount,
            lastMessageBody: lastMessageBody,
            lastMessageType: lastMessageType,
            lastMessageAt: lastMessageAt
        )
    }

    @Test
    func upsertCreatesAndOverwrites() async throws {
        let container = try makeContainer()
        let store = ConversationMetaStore(modelContainer: container)

        try await store.upsert(
            snap(conversationId: 7,
                 peerUserId: 99, peerUsername: "p1", peerDisplayName: "Peer 1",
                 oldestCachedMessageId: 1, newestCachedMessageId: 10,
                 lastReadMessageId: 5, unreadCount: 5,
                 lastMessageBody: "hi", lastMessageType: "text",
                 lastMessageAt: Date(timeIntervalSince1970: 1_700_000_000))
        )

        let snap1 = try await store.load(conversationId: 7)
        #expect(snap1?.unreadCount == 5)
        #expect(snap1?.peerUsername == "p1")

        try await store.upsert(
            snap(conversationId: 7,
                 peerUserId: 100, peerUsername: "p2", peerDisplayName: "Peer 2",
                 oldestCachedMessageId: 1, newestCachedMessageId: 12,
                 lastReadMessageId: 12, unreadCount: 0,
                 lastMessageBody: "bye", lastMessageType: "text",
                 lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100))
        )

        let snap2 = try await store.load(conversationId: 7)
        #expect(snap2?.unreadCount == 0)
        #expect(snap2?.newestCachedMessageId == 12)
        #expect(snap2?.lastMessageBody == "bye")
        #expect(snap2?.peerUserId == 100)
        #expect(snap2?.peerUsername == "p2")
    }

    @Test
    func loadAllReturnsAllRows() async throws {
        let container = try makeContainer()
        let store = ConversationMetaStore(modelContainer: container)

        try await store.upsert(snap(conversationId: 1))
        try await store.upsert(snap(conversationId: 2))

        let all = try await store.loadAll()
        #expect(Set(all.map(\.conversationId)) == [1, 2])
    }

    @Test
    func deleteAllClearsRows() async throws {
        let container = try makeContainer()
        let store = ConversationMetaStore(modelContainer: container)

        try await store.upsert(snap(conversationId: 1))
        try await store.deleteAll()

        #expect(try await store.loadAll().isEmpty)
        #expect(try await store.load(conversationId: 1) == nil)
    }
}
```

- [ ] **Step 2：跑失败的测试**

```bash
$TEST -only-testing:EchoIMTests/ConversationMetaStoreTests
```

预期：编译失败——`ConversationMetaStore` 不存在。

- [ ] **Step 3：实现 `ConversationMetaStore`**

创建 `ios-app/EchoIM/Core/Storage/ConversationMetaStore.swift`：

```swift
import Foundation
import SwiftData

/// 会话元数据（连续后缀不变式边界 + 冷启动预览）的持久化入口。
/// @Model 不出 actor 边界；出口都用 `ConversationMetaSnapshot`。
@ModelActor
actor ConversationMetaStore {
    func upsert(_ snapshot: ConversationMetaSnapshot) async throws {
        let id = snapshot.conversationId
        let descriptor = FetchDescriptor<ConversationMeta>(
            predicate: #Predicate<ConversationMeta> { $0.conversationId == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.peerUserId = snapshot.peerUserId
            existing.peerUsername = snapshot.peerUsername
            existing.peerDisplayName = snapshot.peerDisplayName
            existing.peerAvatarUrl = snapshot.peerAvatarUrl
            existing.oldestCachedMessageId = snapshot.oldestCachedMessageId
            existing.newestCachedMessageId = snapshot.newestCachedMessageId
            existing.lastReadMessageId = snapshot.lastReadMessageId
            existing.unreadCount = snapshot.unreadCount
            existing.lastMessageBody = snapshot.lastMessageBody
            existing.lastMessageType = snapshot.lastMessageType
            existing.lastMessageAt = snapshot.lastMessageAt
        } else {
            let row = ConversationMeta(
                conversationId: snapshot.conversationId,
                peerUserId: snapshot.peerUserId,
                peerUsername: snapshot.peerUsername,
                peerDisplayName: snapshot.peerDisplayName,
                peerAvatarUrl: snapshot.peerAvatarUrl,
                oldestCachedMessageId: snapshot.oldestCachedMessageId,
                newestCachedMessageId: snapshot.newestCachedMessageId,
                lastReadMessageId: snapshot.lastReadMessageId,
                unreadCount: snapshot.unreadCount,
                lastMessageBody: snapshot.lastMessageBody,
                lastMessageType: snapshot.lastMessageType,
                lastMessageAt: snapshot.lastMessageAt
            )
            modelContext.insert(row)
        }
        try modelContext.save()
    }

    func load(conversationId: Int) async throws -> ConversationMetaSnapshot? {
        let descriptor = FetchDescriptor<ConversationMeta>(
            predicate: #Predicate<ConversationMeta> { $0.conversationId == conversationId }
        )
        return try modelContext.fetch(descriptor).first?.snapshot()
    }

    /// 会话列表冷启动用。按 `lastMessageAt` DESC 排，nil 放最后。
    func loadAll() async throws -> [ConversationMetaSnapshot] {
        let descriptor = FetchDescriptor<ConversationMeta>(
            sortBy: [SortDescriptor(\.lastMessageAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { $0.snapshot() }
    }

    func deleteAll() async throws {
        try modelContext.delete(model: ConversationMeta.self)
        try modelContext.save()
    }
}
```

- [ ] **Step 4：跑测试**

```bash
$TEST -only-testing:EchoIMTests/ConversationMetaStoreTests
```

预期：3 个 case 全绿。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Core/Storage/ConversationMetaStore.swift \
        ios-app/EchoIMTests/ConversationMetaStoreTests.swift \
        ios-app/EchoIM.xcodeproj/project.pbxproj
git commit -m "feat(ios): add ConversationMetaStore @ModelActor"
```

---

### Task 6：`UserSession` 类

**Files:**
- Create: `ios-app/EchoIM/App/UserSession.swift`
- Create: `ios-app/EchoIMTests/UserSessionTests.swift`

- [ ] **Step 1：先写失败的测试**

创建 `ios-app/EchoIMTests/UserSessionTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@Suite
struct UserSessionTests {
    @MainActor
    private func makeSession(userId: Int) throws -> UserSession {
        try UserSession(
            userId: userId,
            apiClient: APIClient(),
            tokenLoader: { nil },
            onUnauthorized: {}
        )
    }

    @MainActor
    @Test
    func bootstrapCreatesDirectoryAndExcludesFromBackup() async throws {
        // 这里不要求服务端真的存在这个用户；UserSession 只用 userId 做本地分库路径。
        // 用随机高位 id，避免误删开发机上真实登录用户的缓存目录。
        let userId = Int.random(in: 900_000_000...999_999_999)
        let dir = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)")

        do {
            // session / ModelContainer 只在这个作用域内活着；离开后再删目录。
            let session = try makeSession(userId: userId)
            _ = session

            #expect(FileManager.default.fileExists(atPath: dir.path))

            let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == true)
        }

        // 释放 ModelContainer 后再删目录，避免和 SwiftData 文件句柄抢时序。
        await Task.yield()
        try? FileManager.default.removeItem(at: dir)
    }

    @MainActor
    @Test
    func messageStoreAndConversationMetaStoreFactoriesReuseContainer() async throws {
        // 不依赖真实服务端用户，只需要一个本地唯一的分库 id。
        let userId = Int.random(in: 900_000_000...999_999_999)
        let dir = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)")

        do {
            let session = try makeSession(userId: userId)
            let store1 = session.messageStore()
            let store2 = session.messageStore()

            // 每次调用 factory 应该返回同一 actor 实例（或至少共享同一 container）。
            // 这里的验证是行为级：往 store1 写 → store2 读得到。
            try await store1.append([
                Message(id: 1, conversationId: 1, senderId: 1,
                        body: "hi", messageType: "text", mediaUrl: nil,
                        createdAt: Date(), clientTempId: nil)
            ])
            let read = try await store2.loadLatest(conversationId: 1, limit: 10)
            #expect(read.count == 1)
        }

        // session + store actor 都离开作用域后，再清理 SwiftData 文件目录。
        await Task.yield()
        try? FileManager.default.removeItem(at: dir)
    }
}
```

- [ ] **Step 2：跑失败的测试**

```bash
$TEST -only-testing:EchoIMTests/UserSessionTests
```

预期：编译失败——`UserSession` 不存在。

- [ ] **Step 3：实现 `UserSession`**

创建 `ios-app/EchoIM/App/UserSession.swift`：

```swift
import Foundation
import Observation
import SwiftData

/// 一个登录用户对应一个 UserSession。不同用户彼此隔离（按 userId 分库），
/// 登出时整体释放（设计 §2.2、§5.5）。
///
/// 不暴露"自清理"方法：删自己 store 文件的时序悖论由 `AppContainer.tearDownSession` 统一接管。
@MainActor
final class UserSession {
    let userId: Int
    let modelContainer: ModelContainer
    private(set) var wsClient: WebSocketClient

    private let apiClient: APIClient
    private let onUnauthorized: () async -> Void
    private let tokenLoader: @MainActor () -> String?

    init(
        userId: Int,
        apiClient: APIClient,
        tokenLoader: @escaping @MainActor () -> String?,
        onUnauthorized: @escaping () async -> Void
    ) throws {
        self.userId = userId
        self.apiClient = apiClient
        self.tokenLoader = tokenLoader
        self.onUnauthorized = onUnauthorized

        let storeURL = URL.applicationSupportDirectory
            .appendingPathComponent("EchoIM/users/\(userId)/cache.sqlite")
        let storeDir = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var dirURL = storeDir
        try dirURL.setResourceValues(resourceValues)

        let schema = Schema([CachedMessage.self, ConversationMeta.self])
        let config = ModelConfiguration(url: storeURL)
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            // schema 对不上（开发中 @Model 改了字段）→ 兜底删库重建。
            try? FileManager.default.removeItem(at: storeDir)
            try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            try dirURL.setResourceValues(resourceValues)
            self.modelContainer = try ModelContainer(for: schema, configurations: config)
        }

        self.wsClient = WebSocketClient(
            tokenProvider: tokenLoader,
            onUnauthorized: { Task { await onUnauthorized() } }
        )
    }

    // MARK: - Session-scoped repositories

    func makeMessageRepository() -> MessageRepository {
        MessageRepositoryImpl(api: apiClient)
    }

    func makeConversationRepository() -> ConversationRepository {
        ConversationRepositoryImpl(api: apiClient)
    }

    // MARK: - SwiftData stores

    func messageStore() -> MessageStore {
        MessageStore(modelContainer: modelContainer)
    }

    func conversationMetaStore() -> ConversationMetaStore {
        ConversationMetaStore(modelContainer: modelContainer)
    }

    // MARK: - WS lifecycle

    func connectWebSocketIfNeeded() {
        wsClient.connectIfNeeded()
    }

    func disconnectWebSocket(reason: WSDisconnectReason) {
        wsClient.disconnect(reason: reason)
    }
}
```

> `WSDisconnectReason` 是 `WebSocketClient.swift` 顶层枚举（非嵌套类型，P3 已存在）；`AppContainer.tearDownSession` 调用时写 `.userInitiated` 仍可（Swift 靠参数类型推断枚举 case），但函数签名里必须显式写全名。

- [ ] **Step 4：跑测试**

```bash
$TEST -only-testing:EchoIMTests/UserSessionTests
```

预期：2 个 case 全绿。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/App/UserSession.swift \
        ios-app/EchoIMTests/UserSessionTests.swift \
        ios-app/EchoIM.xcodeproj/project.pbxproj
git commit -m "feat(ios): add UserSession (per-user ModelContainer + session repositories)"
```

---

### Task 7：`AppContainer` 重构 — 把会话相关资源迁到 `UserSession`

**Files:**
- Modify: `ios-app/EchoIM/App/AppContainer.swift:1-136`（整文件）
- Modify: `ios-app/EchoIMTests/AppContainerTests.swift`（扩展 teardown 三阶段测试）
- Modify: `ios-app/EchoIMTests/AppContainerRefreshTests.swift`（同步 API 变动）

- [ ] **Step 1：先写 / 改失败的测试**

在 `ios-app/EchoIMTests/AppContainerTests.swift` 里追加（或替换 P3 的 teardown 用例）：

```swift
@MainActor
@Test
func tearDownSessionClearsAllUserStateAndFiles() async throws {
    let (container, store) = makeContainer()
    // 不依赖真实服务端用户；这里只验证 AppContainer 对当前 session 的本地资源清理。
    let userId = Int.random(in: 900_000_000...999_999_999)

    // 模拟登录 → 建 session。
    container.handleLoginSuccess(
        AuthResponse(
            token: "dummy",
            user: AuthenticatedUser(id: userId, username: "a", email: "a@b.c",
                                    displayName: nil, avatarUrl: nil)
        )
    )
    // `handleLoginSuccess` 在真实路径里由 LoginViewModel 先写 Keychain；测试里后写，
    // 避免 `session.connectWebSocketIfNeeded()` 拿到 token 后真的尝试连本地 WS。
    try store.save(token: "dummy", userId: userId)

    let sessionBefore = container.session
    #expect(sessionBefore != nil)

    let userDir = URL.applicationSupportDirectory
        .appendingPathComponent("EchoIM/users/\(userId)")
    #expect(FileManager.default.fileExists(atPath: userDir.path))

    await container.tearDownSession()

    #expect(container.session == nil)
    #expect(container.currentUser == nil)
    #expect(!FileManager.default.fileExists(atPath: userDir.path))
    #expect(try store.load() != nil) // tearDownSession 不负责清 Keychain；logout / 401 路径单独清。
    try store.clear()
}
```

- [ ] **Step 2：跑失败的测试**

```bash
$TEST -only-testing:EchoIMTests/AppContainerTests
```

预期：编译失败或运行失败——`container.session` 属性不存在 / 目录删除逻辑缺失。

- [ ] **Step 3：改写 `AppContainer`**

覆盖整个 `ios-app/EchoIM/App/AppContainer.swift`：

```swift
import Foundation
import Observation

/// 登录态无关的资源（token、API client）+ 指向当前登录用户的 `UserSession`。
/// 登出 / token 失效时整体释放 session（设计 §2.2）。
@MainActor
@Observable
final class AppContainer {
    let tokenStore: KeychainTokenStore
    let apiClient: APIClient
    var currentUser: AuthenticatedUser?

    /// 当前登录用户的会话。未登录时 nil。P4 起所有 wsClient / 会话相关 repo 都从这里取。
    private(set) var session: UserSession?

    /// 仅 UI 测试参数 `-uitest-reset-keychain` 会把它设为 true。
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

    // MARK: - Stateless repositories（不绑定 session）

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

    // MARK: - Session lifecycle

    func bootstrap() {
        if resetKeychainOnLaunch {
            try? tokenStore.clear()
            currentUser = nil
            session = nil
            return
        }

        guard let stored = try? tokenStore.load() else {
            currentUser = nil
            session = nil
            return
        }

        currentUser = AuthenticatedUser(
            id: stored.userId,
            username: "(restoring)",
            email: "",
            displayName: nil,
            avatarUrl: nil
        )
        try? bootstrapSession(userId: stored.userId)
    }

    func handleLoginSuccess(_ response: AuthResponse) {
        currentUser = response.user
        try? bootstrapSession(userId: response.user.id)
        session?.connectWebSocketIfNeeded()
    }

    func connectWebSocketIfNeeded() {
        session?.connectWebSocketIfNeeded()
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

    func handleUnauthorized() async {
        try? tokenStore.clear()
        await tearDownSession()
    }

    /// 设计 §5.5 的三阶段清理。必须按顺序：
    /// 1. Nuke 独立清（与 SwiftData 无关）
    /// 2. 放掉 session（含 ModelContainer）+ yield 一次让 actor 排空
    /// 3. 删按 userId 的 store 目录
    func tearDownSession() async {
        let userId = session?.userId

        // 阶段 1：Nuke
        ImagePipeline.shared.cache.removeAll()

        // 阶段 2：释放 session
        session?.disconnectWebSocket(reason: .userInitiated)
        session = nil
        currentUser = nil
        await Task.yield()

        // 阶段 3：删目录（session 已放，SwiftData 的文件句柄此时没有持有者）
        if let userId {
            let dir = URL.applicationSupportDirectory
                .appendingPathComponent("EchoIM/users/\(userId)")
            try? FileManager.default.removeItem(at: dir)
        }
    }

    /// Me 页"清除聊天缓存"按钮入口。保留 session / token，只清 SwiftData + Nuke。
    func clearChatCache() async {
        ImagePipeline.shared.cache.removeAll()
        guard let session else { return }
        try? await session.messageStore().deleteAll()
        try? await session.conversationMetaStore().deleteAll()
    }

    // MARK: - Internal

    private func bootstrapSession(userId: Int) throws {
        session = try UserSession(
            userId: userId,
            apiClient: apiClient,
            tokenLoader: { [tokenStore] in
                (try? tokenStore.load())?.token
            },
            onUnauthorized: { [weak self] in
                await self?.handleUnauthorized()
            }
        )
    }
}
```

在文件顶部补 `import Nuke`（`ImagePipeline` 来自 Nuke，`AvatarView.swift` 已在用 `NukeUI`，Nuke 依赖已接入）：

```swift
import Foundation
import Observation
import Nuke
```

- [ ] **Step 4：跑测试**

```bash
$TEST -only-testing:EchoIMTests/AppContainerTests
$TEST -only-testing:EchoIMTests/AppContainerRefreshTests
```

预期：新 teardown 三阶段用例通过；`AppContainerRefreshTests` 如果因为 `wsClient` 不再是 AppContainer 直属属性而编译失败，把访问点改成 `container.session?.wsClient`。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/App/AppContainer.swift \
        ios-app/EchoIMTests/AppContainerTests.swift \
        ios-app/EchoIMTests/AppContainerRefreshTests.swift
git commit -m "refactor(ios): delegate per-user resources to UserSession; three-phase tearDown"
```

---

### Task 8：`RootView` / `MainTabView` / `ContactsView` 接入 `UserSession`

**Files:**
- Modify: `ios-app/EchoIM/App/RootView.swift:38-52`
- Modify: `ios-app/EchoIM/Features/Main/MainTabView.swift:32-57`
- Modify: `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`（`MainTabView` 的调用处入参调整时，如果 `ConversationsListView` 签名仍是 `repository / messageRepo / wsClient` 明确参数，调用处换成 session.makeXxx / session.wsClient 即可，ConversationsListView 本身不动）
- Modify: `ios-app/EchoIM/Features/Contacts/ContactsView.swift` 的 `MainTabView` 调用处

P3 里 `wsClient` 读自 `container.wsClient`。P4 起改读 `container.session?.wsClient`；repositories 也从 session 拿。

- [ ] **Step 1：改 `RootView.swift` scenePhase 联动**

把当前：

```swift
.onChange(of: scenePhase) { _, newPhase in
    guard container.currentUser != nil else { return }
    switch newPhase {
    case .active:
        container.connectWebSocketIfNeeded()
        container.wsClient?.connectIfNeeded()
    case .background:
        container.wsClient?.disconnect(reason: .userInitiated)
    case .inactive:
        break
    @unknown default:
        break
    }
}
```

改为：

```swift
.onChange(of: scenePhase) { _, newPhase in
    guard let session = container.session else { return }
    switch newPhase {
    case .active:
        session.connectWebSocketIfNeeded()
    case .background:
        session.disconnectWebSocket(reason: .userInitiated)
    case .inactive:
        break
    @unknown default:
        break
    }
}
```

- [ ] **Step 2：改 `MainTabView.swift`**

```swift
private var chatsTab: some View {
    if let session = container.session {
        ConversationsListView(
            repository: session.makeConversationRepository(),
            messageRepo: session.makeMessageRepository(),
            metaStore: session.conversationMetaStore(),
            messageStore: session.messageStore(),
            wsClient: session.wsClient,
            currentUserId: container.currentUser?.id ?? 0,
            tokenProvider: { [tokenStore = container.tokenStore] in
                (try? tokenStore.load())?.token
            }
        )
    } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private var contactsTab: some View {
    if let session = container.session {
        ContactsView(
            friendRepo: container.makeFriendRepository(),
            requestRepo: container.makeFriendRequestRepository(),
            userRepo: container.makeUserRepository(),
            messageRepo: session.makeMessageRepository(),
            conversationRepo: session.makeConversationRepository(),
            messageStore: session.messageStore(),
            metaStore: session.conversationMetaStore(),
            wsClient: session.wsClient,
            currentUserId: container.currentUser?.id ?? 0,
            tokenProvider: { [tokenStore = container.tokenStore] in
                (try? tokenStore.load())?.token
            }
        )
    } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

> `metaStore` / `messageStore` 参数下面 Task 9 会加到 `ConversationsListView` / `ChatView`；`ContactsView` 自己的 init 也要同步加这两个入参（`ContactsView` 里 `navigationDestination(for:)` 会直接构造 `ChatView`，见 `ios-app/EchoIM/Features/Contacts/ContactsView.swift:82-93`）。Task 10 Step 4 一并更新 `ContactsView` 签名与 ChatView 调用点。这里先写入调用点，Task 9/10 把参数接住。

（同步把 `MainTabView.body` 里的 `chatsTab` / `contactsTab` 外层 `some View` 改成 `@ViewBuilder`，如果原来就已经是 `@ViewBuilder` 直接用 `if let` + `else` 结构。）

- [ ] **Step 3：继续执行 Task 9 / Task 10，把视图入参一次接完**

Task 8 只改 `MainTabView` 调用点，`ConversationsListView` / `ContactsView` / `ChatView`
还没接住 `messageStore` / `metaStore`，所以这里**不要单独提交，也不要把失败编译当作可交付状态**。
继续执行 Task 9 / Task 10，把 init 签名、字段存储、下传路径一起补齐后，在 Task 10 Step 6 跑 `$BUILD`。

- [ ] **Step 4：提交策略**

Task 8 / 9 / 10 是一个不可中断的接线切片：不要在 Task 8 之后 commit。
实际执行时把三者合并成 Task 10 Step 7 的一个 commit，主干是
"wire UserSession through to views and stores"。

---

### Task 9：`ConversationsListViewModel` meta-first 渲染

**Files:**
- Modify: `ios-app/EchoIM/Features/Conversations/ConversationsListViewModel.swift:29-86`
- Modify: `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift:12-32`
- Create: `ios-app/EchoIMTests/ConversationsListViewModelCacheTests.swift`
- Modify: `ios-app/EchoIMTests/ConversationsListViewModelTests.swift`（所有 `ConversationsListViewModel(...)` 构造处加 `metaStore: nil`）

- [ ] **Step 1：先写失败的测试**

创建 `ios-app/EchoIMTests/ConversationsListViewModelCacheTests.swift`：

```swift
import Testing
import Foundation
import SwiftData
@testable import EchoIM

@Suite
struct ConversationsListViewModelCacheTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CachedMessage.self, ConversationMeta.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// 测试用 snapshot：peer 字段给一个"看得出是好友 99"的值。
    private func snap(
        conversationId: Int,
        oldestCachedMessageId: Int? = nil,
        newestCachedMessageId: Int? = nil,
        lastReadMessageId: Int? = nil,
        unreadCount: Int = 0,
        lastMessageBody: String? = nil,
        lastMessageType: String? = nil,
        lastMessageAt: Date? = nil
    ) -> ConversationMetaSnapshot {
        ConversationMetaSnapshot(
            conversationId: conversationId,
            peerUserId: 99, peerUsername: "peer99",
            peerDisplayName: "Peer 99", peerAvatarUrl: nil,
            oldestCachedMessageId: oldestCachedMessageId,
            newestCachedMessageId: newestCachedMessageId,
            lastReadMessageId: lastReadMessageId,
            unreadCount: unreadCount,
            lastMessageBody: lastMessageBody,
            lastMessageType: lastMessageType,
            lastMessageAt: lastMessageAt
        )
    }

    @MainActor
    @Test
    func loadRendersCachedMetaBeforeNetwork() async throws {
        let container = try makeContainer()
        let metaStore = ConversationMetaStore(modelContainer: container)
        try await metaStore.upsert(
            snap(conversationId: 1,
                 oldestCachedMessageId: 1, newestCachedMessageId: 5,
                 lastReadMessageId: 3, unreadCount: 2,
                 lastMessageBody: "cached", lastMessageType: "text",
                 lastMessageAt: Date(timeIntervalSince1970: 1_700_000_000))
        )

        // mock repo：延迟 200ms 才返回，留出"先渲染缓存再刷新"的窗口。
        final class DelayedRepo: ConversationRepository {
            func list(token: String) async throws -> [Conversation] {
                try await Task.sleep(nanoseconds: 200_000_000)
                return []  // 服务端说：这个用户没有会话
            }
        }

        let vm = ConversationsListViewModel(
            repository: DelayedRepo(),
            metaStore: metaStore,
            tokenProvider: { "t" },
            currentUserId: { 10 }
        )

        async let loading: Void = vm.load()

        // 50ms 后缓存应该已经渲染（还没等到网络）。
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.conversations.count == 1)
        #expect(vm.conversations.first?.lastMessageBody == "cached")
        #expect(vm.conversations.first?.peer.username == "peer99")

        await loading
        #expect(vm.conversations.isEmpty)  // 网络覆盖缓存
    }

    @MainActor
    @Test
    func refreshWritesBackToMetaStore() async throws {
        let container = try makeContainer()
        let metaStore = ConversationMetaStore(modelContainer: container)

        final class StubRepo: ConversationRepository {
            func list(token: String) async throws -> [Conversation] {
                let peer = UserProfile(id: 99, username: "p", displayName: nil, avatarUrl: nil)
                return [
                    Conversation(
                        id: 7, createdAt: Date(),
                        peer: peer,
                        lastMessageBody: "fresh", lastMessageType: "text",
                        lastMessageSenderId: 99, lastMessageAt: Date(timeIntervalSince1970: 1_700_000_500),
                        lastReadMessageId: 100, unreadCount: 3
                    )
                ]
            }
        }

        let vm = ConversationsListViewModel(
            repository: StubRepo(),
            metaStore: metaStore,
            tokenProvider: { "t" },
            currentUserId: { 10 }
        )

        await vm.load()
        let snap = try await metaStore.load(conversationId: 7)
        #expect(snap?.lastMessageBody == "fresh")
        #expect(snap?.unreadCount == 3)
    }
}
```

`UserProfile` / `Conversation` 构造参数以 `ios-app/EchoIM/Core/Networking/Models/Conversation.swift` / `UserProfile.swift` 里实际 `init` 为准；如果没有 memberwise `init`（大概率 `Conversation` 只给了 `Decodable` 的 `init(from:)`），需要给 `Conversation` 加一个 `internal init(...)`（Task 3/已有）或用专用 `makeConversationForTest` 工厂。**优先方案**：走 JSON 字符串 decode 生成 `Conversation` 对象，避开 init 歧义。

- [ ] **Step 2：跑失败的测试**

```bash
$TEST -only-testing:EchoIMTests/ConversationsListViewModelCacheTests
```

预期：编译失败——`ConversationsListViewModel` 构造不接受 `metaStore`。

- [ ] **Step 3：改 `ConversationsListViewModel`**

覆盖：

```swift
@Observable
@MainActor
final class ConversationsListViewModel {
    private(set) var conversations: [Conversation] = []
    private(set) var phase: ConversationsPhase = .idle

    private let repository: ConversationRepository
    private let metaStore: ConversationMetaStore?
    private let tokenProvider: @MainActor () -> String?
    private let currentUserId: @MainActor () -> Int?
    private weak var wsClient: WebSocketClient?
    private var wsSubscription: WSSubscription?
    private var readySubscription: WSSubscription?

    init(
        repository: ConversationRepository,
        metaStore: ConversationMetaStore? = nil,
        tokenProvider: @escaping @MainActor () -> String?,
        currentUserId: @escaping @MainActor () -> Int? = { nil },
        wsClient: WebSocketClient? = nil
    ) {
        self.repository = repository
        self.metaStore = metaStore
        self.tokenProvider = tokenProvider
        self.currentUserId = currentUserId
        self.wsClient = wsClient
    }

    // MARK: - Load

    func load() async {
        if phase == .loading { return }

        // 阶段 1：缓存命中即刻渲染（没网或网慢时不阻塞）。
        if let metaStore, conversations.isEmpty {
            if let snapshots = try? await metaStore.loadAll(), !snapshots.isEmpty {
                conversations = snapshots.map(Conversation.fromCachedMeta)
                // phase 保留为 idle，等后面真正 network call 完成再翻到 loaded
            }
        }

        await refresh()
    }

    func refresh() async {
        guard let token = tokenProvider() else {
            phase = .unauthenticated
            return
        }

        phase = .loading

        do {
            let fresh = try await repository.list(token: token)
            conversations = fresh
            phase = .loaded
            await writeBack(fresh)
        } catch {
            phase = .error(String(describing: error))
        }
    }

    private func writeBack(_ conversations: [Conversation]) async {
        guard let metaStore else { return }
        for conv in conversations {
            let existing = try? await metaStore.load(conversationId: conv.id)
            let merged = ConversationMetaSnapshot(
                conversationId: conv.id,
                peerUserId: conv.peer.id,
                peerUsername: conv.peer.username,
                peerDisplayName: conv.peer.displayName,
                peerAvatarUrl: conv.peer.avatarUrl,
                // oldest / newest 是消息边界，不能被会话列表覆盖；保留老值。
                oldestCachedMessageId: existing?.oldestCachedMessageId,
                newestCachedMessageId: existing?.newestCachedMessageId,
                lastReadMessageId: conv.lastReadMessageId,
                unreadCount: conv.unreadCount,
                lastMessageBody: conv.lastMessageBody,
                lastMessageType: conv.lastMessageType,
                lastMessageAt: conv.lastMessageAt
            )
            try? await metaStore.upsert(merged)
        }
    }

    // ... 其余（attachWSSubscription / detachWSSubscription / handleWSEvent / applyIncomingMessage /
    //      applyConversationUpdated）保持 P3 实现不变
}

// 文件底部新增：
extension Conversation {
    /// 冷启动 / 缓存渲染用：从 ConversationMetaSnapshot 合成 Conversation。
    /// peer 信息由 §5.2 的 ConversationMeta peer 字段提供，**不再是占位空字符串**。
    static func fromCachedMeta(_ snap: ConversationMetaSnapshot) -> Conversation {
        Conversation(
            id: snap.conversationId,
            createdAt: Date(),
            peer: UserProfile(
                id: snap.peerUserId,
                username: snap.peerUsername,
                displayName: snap.peerDisplayName,
                avatarUrl: snap.peerAvatarUrl
            ),
            lastMessageBody: snap.lastMessageBody,
            lastMessageType: snap.lastMessageType,
            lastMessageSenderId: nil,
            lastMessageAt: snap.lastMessageAt,
            lastReadMessageId: snap.lastReadMessageId,
            unreadCount: snap.unreadCount
        )
    }
}
```

> **`Conversation` / `UserProfile` memberwise init**：两者 struct 主体都没有显式 init（`Decodable.init(from:)` 写在 extension 里），Swift 自动合成 `internal` memberwise init；测试与实现代码可直接 `Conversation(id:createdAt:peer:...)` / `UserProfile(id:username:displayName:avatarUrl:)` 构造。

> 这里展示的是 meta-first 的核心改造。`writeBack` 只写服务端刚回的 conversations，**不写 WS `message.new` 增量更新**——增量更新在 `applyIncomingMessage` 里只改内存，持久化由下一次 `refresh` 兜底，避免 WS 风暴写盘。

- [ ] **Step 4：改 `ConversationsListView.swift`**

把 `init` 加上 `metaStore` 参数：

```swift
init(
    repository: ConversationRepository,
    messageRepo: MessageRepository,
    metaStore: ConversationMetaStore?,
    messageStore: MessageStore?,
    wsClient: WebSocketClient?,
    currentUserId: Int,
    tokenProvider: @escaping @MainActor () -> String?
) {
    _vm = State(
        wrappedValue: ConversationsListViewModel(
            repository: repository,
            metaStore: metaStore,
            tokenProvider: tokenProvider,
            currentUserId: { currentUserId },
            wsClient: wsClient
        )
    )
    self.conversationRepo = repository
    self.messageRepo = messageRepo
    self.messageStore = messageStore
    self.metaStore = metaStore
    self.wsClient = wsClient
    self.currentUserId = currentUserId
    self.tokenProvider = tokenProvider
}
```

对应新增两个存字段：

```swift
private let messageStore: MessageStore?
private let metaStore: ConversationMetaStore?
```

`destination(for:)` 构造 `ChatView` 时把 `messageStore` / `metaStore` 透传下去（Task 10 会在 ChatView 接住）：

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
        tokenProvider: { tokenProvider() }
    )
}
```

- [ ] **Step 5：改 `ConversationsListViewModelTests` 里所有构造处**

批量加 `metaStore: nil`：

```bash
grep -rn "ConversationsListViewModel(" ios-app/EchoIMTests
```

把没有 `metaStore:` 的改为加上 `metaStore: nil,`（放在 `repository:` 之后）。

- [ ] **Step 6：跑测试**

```bash
$TEST -only-testing:EchoIMTests/ConversationsListViewModelCacheTests
$TEST -only-testing:EchoIMTests/ConversationsListViewModelTests
```

预期：缓存用例 2 条通过；P3 既有用例不回归。

- [ ] **Step 7：暂不 commit**——ChatView 侧参数还没接入（Task 10），编译整体仍失败。执行时与 Task 10 合并提交。

---

### Task 10：`ChatViewModel` 注入 stores + write-through

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`
- Modify: `ios-app/EchoIM/Features/Chat/ChatView.swift`
- Modify: `ios-app/EchoIMTests/ChatViewModelLoadTests.swift` / `ChatViewModelWSTests.swift` / `ChatViewModelSendTests.swift` / `ChatViewModelReadTests.swift`（所有 `ChatViewModel(...)` 构造处加 `messageStore: nil, metaStore: nil`）

本 task 只做"注入 stores + write-through + 场景 A 改造"。场景 C 循环翻页 + 20 页安全阀放 Task 11；`loadOlder` 本地优先放 Task 12。

- [ ] **Step 1：先写失败的测试**

创建 `ios-app/EchoIMTests/ChatViewModelCacheTests.swift`：

```swift
import Testing
import Foundation
import SwiftData
@testable import EchoIM

@Suite
struct ChatViewModelCacheTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CachedMessage.self, ConversationMeta.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makePeer() -> UserProfile {
        UserProfile(id: 20, username: "peer", displayName: nil, avatarUrl: nil)
    }

    /// 测试用 meta snapshot；peer 字段自动补齐。
    private func metaSnap(
        conversationId: Int = 7,
        oldestCachedMessageId: Int? = nil,
        newestCachedMessageId: Int? = nil,
        lastReadMessageId: Int? = nil,
        unreadCount: Int = 0,
        lastMessageBody: String? = nil,
        lastMessageType: String? = nil,
        lastMessageAt: Date? = nil
    ) -> ConversationMetaSnapshot {
        ConversationMetaSnapshot(
            conversationId: conversationId,
            peerUserId: 20, peerUsername: "peer",
            peerDisplayName: nil, peerAvatarUrl: nil,
            oldestCachedMessageId: oldestCachedMessageId,
            newestCachedMessageId: newestCachedMessageId,
            lastReadMessageId: lastReadMessageId,
            unreadCount: unreadCount,
            lastMessageBody: lastMessageBody,
            lastMessageType: lastMessageType,
            lastMessageAt: lastMessageAt
        )
    }

    @MainActor
    @Test
    func loadRendersCachedMessagesBeforeNetwork() async throws {
        let container = try makeContainer()
        let messageStore = MessageStore(modelContainer: container)
        let metaStore = ConversationMetaStore(modelContainer: container)

        // 预置缓存：id 1..3
        try await messageStore.append((1...3).map {
            Message(id: $0, conversationId: 7, senderId: 20, body: "cached-\($0)",
                    messageType: "text", mediaUrl: nil,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                    clientTempId: nil)
        })
        try await metaStore.upsert(metaSnap(
            oldestCachedMessageId: 1, newestCachedMessageId: 3,
            lastReadMessageId: 3, unreadCount: 0,
            lastMessageBody: "cached-3", lastMessageType: "text",
            lastMessageAt: Date(timeIntervalSince1970: 1_700_000_003)
        ))

        final class DelayedRepo: MessageRepository {
            func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] {
                try await Task.sleep(nanoseconds: 200_000_000)
                return []  // 服务端什么都没变
            }
            func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
                fatalError()
            }
            func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
        }

        let conversation = Conversation(
            id: 7, createdAt: Date(), peer: makePeer(),
            lastMessageBody: "cached-3", lastMessageType: "text",
            lastMessageSenderId: 20, lastMessageAt: Date(),
            lastReadMessageId: 3, unreadCount: 0
        )
        let vm = ChatViewModel(
            route: .conversation(conversation),
            currentUserId: 10,
            messageRepo: DelayedRepo(),
            wsClient: nil,
            conversationRepository: nil,
            messageStore: messageStore,
            metaStore: metaStore,
            tokenProvider: { "t" }
        )

        async let loading: Void = vm.load()

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.messages.count == 3)
        #expect(vm.messages.map(\.message.id) == [1, 2, 3])

        await loading
        #expect(vm.phase == .loaded)
    }

    @MainActor
    @Test
    func loadWritesNetworkResultToCache() async throws {
        let container = try makeContainer()
        let messageStore = MessageStore(modelContainer: container)
        let metaStore = ConversationMetaStore(modelContainer: container)

        final class StubRepo: MessageRepository {
            func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] {
                // 服务端 DESC：最新在前
                return (1...10).reversed().map {
                    Message(id: $0, conversationId: 7, senderId: 20, body: "m-\($0)",
                            messageType: "text", mediaUrl: nil,
                            createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                            clientTempId: nil)
                }
            }
            func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
                fatalError()
            }
            func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
        }

        let vm = ChatViewModel(
            route: .conversation(Conversation(
                id: 7, createdAt: Date(), peer: makePeer(),
                lastMessageBody: nil, lastMessageType: nil,
                lastMessageSenderId: nil, lastMessageAt: nil,
                lastReadMessageId: nil, unreadCount: 0
            )),
            currentUserId: 10,
            messageRepo: StubRepo(),
            wsClient: nil,
            conversationRepository: nil,
            messageStore: messageStore,
            metaStore: metaStore,
            tokenProvider: { "t" }
        )

        await vm.load()

        let cached = try await messageStore.loadLatest(conversationId: 7, limit: 50)
        #expect(cached.count == 10)
        let meta = try await metaStore.load(conversationId: 7)
        #expect(meta?.oldestCachedMessageId == 1)
        #expect(meta?.newestCachedMessageId == 10)
    }
}
```

（循环翻页 / loadOlder 本地优先的测试留给 Task 11 / 12。）

- [ ] **Step 2：跑失败的测试**

```bash
$TEST -only-testing:EchoIMTests/ChatViewModelCacheTests
```

预期：编译失败——`ChatViewModel` 构造不接 `messageStore` / `metaStore`。

- [ ] **Step 3：改 `ChatViewModel`**

核心改动：

1. `init` 加两个可选入参 `messageStore: MessageStore?` / `metaStore: ConversationMetaStore?`，保存到私有字段
2. `load()` 前置读缓存（场景 A 的本地命中分支）
3. `load()` / `loadOlder()` / `refetchMissedMessages()` / `handleIncomingMessage` / `mergeServerResult` 等"产生 confirmed 消息"的路径都走 write-through
4. `markReadIfNeeded()` 推进 `lastReadMessageId` 后，同步推进 meta

具体 diff 要点（只列改动，不变的代码保留）：

```swift
// 新增字段
private let messageStore: MessageStore?
private let metaStore: ConversationMetaStore?

// 新 init（替换 P3 init）
init(
    route: ChatRoute,
    currentUserId: Int,
    messageRepo: MessageRepository,
    wsClient: WebSocketClient?,
    conversationRepository: ConversationRepository? = nil,
    messageStore: MessageStore? = nil,
    metaStore: ConversationMetaStore? = nil,
    tokenProvider: @escaping @MainActor () -> String?
) {
    // 原有 route switch + 字段赋值...
    self.messageStore = messageStore
    self.metaStore = metaStore
}

// load() 改写
func load() async {
    guard let conversationId else {
        phase = .loaded
        hasMoreOlder = false
        return
    }
    guard let token = tokenProvider() else {
        phase = .error("unauthenticated")
        return
    }

    // 阶段 1：缓存命中即刻渲染
    if messages.isEmpty, let messageStore {
        if let cached = try? await messageStore.loadLatest(conversationId: conversationId, limit: 50),
           !cached.isEmpty {
            // loadLatest 返回 DESC，翻转为旧→新展示
            messages = cached.reversed().map(LocalMessage.confirmed)
            phase = .loaded
        }
    }

    // 阶段 2：总是向服务端要一次最新（§5.3 场景 A；有缓存 → 场景 B 交给 refetchMissedMessages）
    if messages.isEmpty {
        // 场景 A：无 cursor 拉最新 50
        do {
            let rows = try await messageRepo.list(
                conversationId: conversationId,
                cursor: nil,
                limit: nil,   // 默认 50
                token: token
            )
            messages = rows.reversed().map(LocalMessage.confirmed)
            hasMoreOlder = rows.count == 50
            phase = .loaded
            await writeThroughAndMeta(rows)
            await markReadIfNeeded()
        } catch {
            if messages.isEmpty {
                phase = .error(String(describing: error))
            }
        }
    } else {
        // 场景 B：有缓存，只要 after 增量——交给 refetchMissedMessages（Task 11 升级为循环翻页）
        await refetchMissedMessages()
        await markReadIfNeeded()
    }
}

// 新增 write-through 助手
private func writeThroughAndMeta(_ rows: [Message]) async {
    guard let messageStore, let metaStore else { return }
    guard let conversationId, !rows.isEmpty else { return }

    try? await messageStore.append(rows)

    // 按 id 判"谁最新"——服务端 SERIAL 全局单调，id 大 = 时间晚，与 rows 排序方向（DESC/ASC）无关。
    // 避免 `rows.last` 在 DESC 场景（load 场景 A）里反而是最旧那条的 bug。
    let newestInBatch = rows.max(by: { $0.id < $1.id })
    let minNew = rows.map(\.id).min() ?? 0
    let maxNew = newestInBatch?.id ?? 0

    let existing = try? await metaStore.load(conversationId: conversationId)

    // 只有 "批内最新 id > 已记录最新 id" 才更新预览字段，避免 loadOlder 把旧消息覆盖成 last preview
    let shouldReplacePreview = maxNew > (existing?.newestCachedMessageId ?? 0)

    let merged = ConversationMetaSnapshot(
        conversationId: conversationId,
        // peer 来自 VM 里已知的 peer；meta 第一次建立时写入，之后的 ChatViewModel 写盘也补齐
        peerUserId: existing?.peerUserId ?? peer.id,
        peerUsername: existing?.peerUsername ?? peer.username,
        peerDisplayName: existing?.peerDisplayName ?? peer.displayName,
        peerAvatarUrl: existing?.peerAvatarUrl ?? peer.avatarUrl,
        oldestCachedMessageId: min(existing?.oldestCachedMessageId ?? .max, minNew),
        newestCachedMessageId: max(existing?.newestCachedMessageId ?? .min, maxNew),
        lastReadMessageId: existing?.lastReadMessageId ?? lastReadMessageId,
        unreadCount: existing?.unreadCount ?? 0,
        lastMessageBody: shouldReplacePreview ? newestInBatch?.body : existing?.lastMessageBody,
        lastMessageType: shouldReplacePreview ? newestInBatch?.messageType : existing?.lastMessageType,
        lastMessageAt: shouldReplacePreview ? newestInBatch?.createdAt : existing?.lastMessageAt
    )
    try? await metaStore.upsert(merged)
}

// mergeServerResult：confirmed 时也写 store
fileprivate func mergeServerResult(_ message: Message, tempId: String) {
    if conversationId == nil {
        conversationId = message.conversationId
    }

    if let index = messages.firstIndex(where: { $0.localId == tempId }) {
        messages[index] = LocalMessage(
            localId: "id-\(message.id)",
            message: message,
            sendState: .confirmed,
            localImageData: messages[index].localImageData
        )
    } else if !messages.contains(where: { $0.message.id == message.id }) {
        messages.append(LocalMessage.confirmed(message))
    }

    // write-through
    Task { [weak self] in
        await self?.writeThroughAndMeta([message])
    }
}

// handleIncomingMessage：confirmed 消息入库
private func handleIncomingMessage(_ incoming: Message) {
    // ...（保持 P3 的 conversationId 回填与 echo merge 逻辑）...
    guard !messages.contains(where: { $0.message.id == incoming.id }) else { return }
    messages.append(.confirmed(incoming))

    Task { [weak self] in
        await self?.writeThroughAndMeta([incoming])
    }

    if incoming.senderId != currentUserId {
        Task { [weak self] in
            await self?.markReadIfNeeded()
        }
    }
}

// markReadIfNeeded 尾部：推进 meta 的 lastReadMessageId
func markReadIfNeeded() async {
    // ...（保持 P3 实现）...
    do {
        try await messageRepo.markRead(
            conversationId: conversationId,
            lastReadMessageId: latest,
            token: token
        )
        lastReadMessageId = latest
        if let metaStore, let existing = try? await metaStore.load(conversationId: conversationId) {
            try? await metaStore.upsert(
                ConversationMetaSnapshot(
                    conversationId: existing.conversationId,
                    peerUserId: existing.peerUserId,
                    peerUsername: existing.peerUsername,
                    peerDisplayName: existing.peerDisplayName,
                    peerAvatarUrl: existing.peerAvatarUrl,
                    oldestCachedMessageId: existing.oldestCachedMessageId,
                    newestCachedMessageId: existing.newestCachedMessageId,
                    lastReadMessageId: latest,
                    unreadCount: 0,
                    lastMessageBody: existing.lastMessageBody,
                    lastMessageType: existing.lastMessageType,
                    lastMessageAt: existing.lastMessageAt
                )
            )
        }
    } catch { /* 静默 */ }
}
```

- [ ] **Step 4：改 `ChatView.swift` init**

```swift
init(
    route: ChatRoute,
    currentUserId: Int,
    messageRepo: MessageRepository,
    messageStore: MessageStore?,
    metaStore: ConversationMetaStore?,
    wsClient: WebSocketClient?,
    conversationRepository: ConversationRepository?,
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
            tokenProvider: tokenProvider
        )
    )
}
```

- [ ] **Step 4b：改 `ContactsView.swift` 接住 store 并下传到 ChatView**

`ContactsView` 自己 `navigationDestination(for:)` 里构造 ChatView（`ios-app/EchoIM/Features/Contacts/ContactsView.swift:82`），必须也拿到 `messageStore` / `metaStore`，否则从"联系人 → 点好友 → 进聊天"这条路径拿不到缓存。

1. 在 `ContactsView` 的 init 里加参数 `messageStore: MessageStore?` / `metaStore: ConversationMetaStore?`，对应存字段：

```swift
private let messageStore: MessageStore?
private let metaStore: ConversationMetaStore?

init(
    friendRepo: FriendRepository,
    requestRepo: FriendRequestRepository,
    userRepo: UserRepository,
    messageRepo: MessageRepository,
    conversationRepo: ConversationRepository,
    messageStore: MessageStore?,
    metaStore: ConversationMetaStore?,
    wsClient: WebSocketClient?,
    currentUserId: Int,
    tokenProvider: @escaping () -> String?
) {
    // ...（原有赋值）...
    self.messageStore = messageStore
    self.metaStore = metaStore
}
```

2. `navigationDestination(for: ChatRoute.self)` 里的 ChatView 构造改成：

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
        tokenProvider: { tokenProvider() }
    )
}
```

（这一步是 Task 8 Step 2 里 `MainTabView.contactsTab` 已经传 `messageStore: session.messageStore(), metaStore: session.conversationMetaStore()` 的配对端——没有这一步编译会挂，因为 `ContactsView.init` 不接这两个参数。）

- [ ] **Step 5：同步修所有现有测试构造处**

```bash
grep -rn "ChatViewModel(" ios-app/EchoIMTests
```

每处加：`messageStore: nil, metaStore: nil,` （放在 `conversationRepository:` 之后 `tokenProvider:` 之前）。

- [ ] **Step 6：编译 + 跑全量测试**

```bash
$BUILD
$TEST
```

预期：`ChatViewModelCacheTests` 2 条新用例通过；P3 既有 ChatViewModel / ConversationsListViewModel / AppContainer 相关测试不回归。

- [ ] **Step 7：合并 Task 8/9/10 的改动一起提交**

```bash
git add ios-app/EchoIM/App/RootView.swift \
        ios-app/EchoIM/Features/Main/MainTabView.swift \
        ios-app/EchoIM/Features/Conversations/ConversationsListView.swift \
        ios-app/EchoIM/Features/Conversations/ConversationsListViewModel.swift \
        ios-app/EchoIM/Features/Contacts/ContactsView.swift \
        ios-app/EchoIM/Features/Chat/ChatView.swift \
        ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
        ios-app/EchoIMTests/ChatViewModelCacheTests.swift \
        ios-app/EchoIMTests/ConversationsListViewModelCacheTests.swift \
        $(grep -rln "ChatViewModel(" ios-app/EchoIMTests) \
        $(grep -rln "ConversationsListViewModel(" ios-app/EchoIMTests) \
        ios-app/EchoIM.xcodeproj/project.pbxproj
git commit -m "feat(ios): wire stores through views and write-through cache on load/WS/send"
```

---

### Task 11：`refetchMissedMessages` 升级为循环翻页 + 20 页安全阀（设计 §5.3 场景 C）

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift:320-346`（`refetchMissedMessages` 方法体）
- Modify: `ios-app/EchoIMTests/ChatViewModelCacheTests.swift`（追加循环翻页用例）

- [ ] **Step 1：先写失败的测试**

在 `ChatViewModelCacheTests.swift` 末尾追加：

```swift
@MainActor
@Test
func refetchLoopsUntilSmallPage() async throws {
    let container = try makeContainer()
    let messageStore = MessageStore(modelContainer: container)
    let metaStore = ConversationMetaStore(modelContainer: container)

    // 场景：本地 newest = 100（meta 中），服务端从 101 起新增了 120 条（101..220），
    //       refetch 预期分 3 页（50 + 50 + 20）打满，直到返回 < 50 才停。
    actor PagedRepo: MessageRepository {
        private(set) var calls = 0
        func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] {
            calls += 1
            guard case let .after(anchor)? = cursor else { return [] }
            let upperBound = 220
            let upper = min(anchor + 50, upperBound)
            if upper <= anchor { return [] }
            return (anchor+1...upper).map {
                Message(id: $0, conversationId: 7, senderId: 20, body: "m-\($0)",
                        messageType: "text", mediaUrl: nil,
                        createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                        clientTempId: nil)
            }
        }
        func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
            fatalError()
        }
        func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
    }

    // 预置本地连续后缀：缓存里已有 51..100；meta 与 messageStore 必须一致，
    // 这样 refetch 才是在真实的"场景 C：从 newest=100 往后追 101..220"。
    try await messageStore.append((51...100).map {
        Message(id: $0, conversationId: 7, senderId: 20, body: "m-\($0)",
                messageType: "text", mediaUrl: nil,
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                clientTempId: nil)
    })
    try await metaStore.upsert(metaSnap(
        oldestCachedMessageId: 51, newestCachedMessageId: 100,
        lastReadMessageId: 100, unreadCount: 0,
        lastMessageBody: "m-100", lastMessageType: "text",
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100)
    ))

    let conversation = Conversation(
        id: 7, createdAt: Date(),
        peer: makePeer(),
        lastMessageBody: "m-100", lastMessageType: "text",
        lastMessageSenderId: 20, lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100),
        lastReadMessageId: 100, unreadCount: 0
    )
    let repo = PagedRepo()
    let vm = ChatViewModel(
        route: .conversation(conversation),
        currentUserId: 10,
        messageRepo: repo,
        wsClient: nil,
        conversationRepository: nil,
        messageStore: messageStore,
        metaStore: metaStore,
        tokenProvider: { "t" }
    )

    await vm.refetchMissedMessages()   // 触发循环

    // 重点断言：调了 3 次 repo（50 + 50 + 20）
    let n = await repo.calls
    #expect(n == 3)
    // 缓存补齐后应保留原 51..100，再追加 101..220，形成连续后缀 51..220
    let cached = try await messageStore.loadLatest(conversationId: 7, limit: 200)
    #expect(cached.count == 170)
    #expect(cached.first?.id == 220)    // DESC 返回，最新在前
    let meta = try await metaStore.load(conversationId: 7)
    #expect(meta?.oldestCachedMessageId == 51)
    #expect(meta?.newestCachedMessageId == 220)
}
```

（如果 `refetchMissedMessages` 从 `messages` 推算 newest 导致起点不对，在 VM 上暴露一个 test-only `setDebugMessages(_:)` 或在 §5.3 实现里改为"优先读 meta.newestCachedMessageId，否则看 messages"。下一步 Step 3 会保证这一点。）

- [ ] **Step 2：跑失败的测试**

```bash
$TEST -only-testing:EchoIMTests/ChatViewModelCacheTests/refetchLoopsUntilSmallPage
```

预期：断言失败——P3 版本只调 1 次 repo。

- [ ] **Step 3：改 `refetchMissedMessages`**

```swift
/// §5.3 场景 C：从当前 newest 开始循环 after-cursor 翻页，直到返回 < limit（说明追上了）。
/// 安全阀：单次补拉最多 20 页（1000 条）；超过停止并日志告警（P4 仅静默，P8 接日志）。
func refetchMissedMessages() async {
    guard let conversationId else { return }
    guard let token = tokenProvider() else { return }

    // 起点：优先 meta（重连场景下 messages 可能为空）；否则看当前 messages 的 max confirmed id
    var cursor: Int = 0
    if let metaStore, let meta = try? await metaStore.load(conversationId: conversationId) {
        cursor = meta.newestCachedMessageId ?? 0
    }
    if cursor == 0 {
        cursor = messages.reduce(into: 0) { result, localMessage in
            if case .confirmed = localMessage.sendState {
                result = max(result, localMessage.message.id)
            }
        }
    }

    guard cursor > 0 else {
        // 没有任何本地锚点 → 走场景 A 全量拉
        await load()
        return
    }

    let pageSize = 50
    let maxPages = 20
    var pages = 0
    while pages < maxPages {
        pages += 1
        do {
            let rows = try await messageRepo.list(
                conversationId: conversationId,
                cursor: .after(cursor),
                limit: pageSize,
                token: token
            )
            guard !rows.isEmpty else { return }

            for message in rows where !messages.contains(where: { $0.message.id == message.id }) {
                messages.append(.confirmed(message))
            }
            await writeThroughAndMeta(rows)

            if let newCursor = rows.map(\.id).max() { cursor = newCursor }
            if rows.count < pageSize { return }
        } catch {
            return   // 一次失败就停；下一次 ready / 重进页面会再尝试
        }
    }

    // 到 20 页仍没追上 → 作品集范围接受这个妥协（设计 §10 已知限制）。
}
```

（把 `refetchMissedMessages` 的可见性从 P3 的 internal 保留；若 Swift Testing 要求 `private` 可测，追加 `@testable import EchoIM`。）

- [ ] **Step 4：跑测试**

```bash
$TEST -only-testing:EchoIMTests/ChatViewModelCacheTests
```

预期：`refetchLoopsUntilSmallPage` + 前两条场景 A/B 用例全绿；P3 既有测试不回归。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
        ios-app/EchoIMTests/ChatViewModelCacheTests.swift
git commit -m "feat(ios): loop paginate refetchMissedMessages with 20-page safety cap"
```

---

### Task 12：`loadOlder` 本地优先 + 远端补缺（设计 §5.3 上滑段）

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift:99-119`（`loadOlder` 方法）
- Modify: `ios-app/EchoIMTests/ChatViewModelCacheTests.swift`（追加 2 用例）

- [ ] **Step 1：先写失败的测试**

在 `ChatViewModelCacheTests.swift` 末尾追加：

```swift
@MainActor
@Test
func loadOlderFullyServedByCacheSkipsNetwork() async throws {
    let container = try makeContainer()
    let messageStore = MessageStore(modelContainer: container)
    let metaStore = ConversationMetaStore(modelContainer: container)

    // 预置缓存 id 1..100（100 条连续后缀）：
    // load() 取最新 50（51..100），loadOlder 本地再取 50（1..50）→ 本地够用，零网络。
    try await messageStore.append((1...100).map {
        Message(id: $0, conversationId: 7, senderId: 20, body: "m-\($0)",
                messageType: "text", mediaUrl: nil,
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                clientTempId: nil)
    })
    try await metaStore.upsert(metaSnap(
        oldestCachedMessageId: 1, newestCachedMessageId: 100,
        lastReadMessageId: 100, unreadCount: 0,
        lastMessageBody: "m-100", lastMessageType: "text",
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100)
    ))

    actor StrictRepo: MessageRepository {
        private(set) var calls = 0
        func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] {
            calls += 1
            return []   // 服务端从此以后什么都不给
        }
        func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message { fatalError() }
        func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
        func resetCalls() { calls = 0 }
    }

    let conversation = Conversation(
        id: 7, createdAt: Date(),
        peer: makePeer(),
        lastMessageBody: "m-100", lastMessageType: "text", lastMessageSenderId: 20,
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100),
        lastReadMessageId: 100, unreadCount: 0
    )
    let repo = StrictRepo()
    let vm = ChatViewModel(
        route: .conversation(conversation),
        currentUserId: 10,
        messageRepo: repo,
        wsClient: nil,
        conversationRepository: nil,
        messageStore: messageStore,
        metaStore: metaStore,
        tokenProvider: { "t" }
    )

    await vm.load()
    // 渲染 51..100（`loadLatest(limit: 50)` 返回最新 50）；
    // load 里还会调 refetchMissedMessages（after=100 返回空，1 次 call）。
    #expect(vm.messages.count == 50)
    #expect(vm.messages.first?.message.id == 51)
    #expect(vm.messages.last?.message.id == 100)

    await repo.resetCalls()

    await vm.loadOlder()

    let n = await repo.calls
    #expect(n == 0)                         // 本地 50 条刚好喂满，零网络
    #expect(vm.messages.count == 100)       // 1..100 全在列表里
    #expect(vm.messages.first?.message.id == 1)
}

@MainActor
@Test
func loadOlderPartialCacheHitsSupplementsFromRemote() async throws {
    let container = try makeContainer()
    let messageStore = MessageStore(modelContainer: container)
    let metaStore = ConversationMetaStore(modelContainer: container)

    // 预置缓存 id 41..100（60 条）：load() 取 51..100，loadOlder 本地吃 41..50（10 条），
    // 还差 40 条 → 远端 before=41&limit=40 返回 1..40。
    try await messageStore.append((41...100).map {
        Message(id: $0, conversationId: 7, senderId: 20, body: "m-\($0)",
                messageType: "text", mediaUrl: nil,
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                clientTempId: nil)
    })
    try await metaStore.upsert(metaSnap(
        oldestCachedMessageId: 41, newestCachedMessageId: 100,
        lastReadMessageId: 100, unreadCount: 0,
        lastMessageBody: "m-100", lastMessageType: "text",
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100)
    ))

    actor RecordingRepo: MessageRepository {
        private(set) var lastBeforeAnchor: Int?
        private(set) var lastLimit: Int?
        private(set) var beforeCalls = 0
        func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] {
            switch cursor {
            case .before(let anchor):
                beforeCalls += 1
                lastBeforeAnchor = anchor
                lastLimit = limit
                let count = min(limit ?? 50, anchor - 1)
                guard count > 0 else { return [] }
                // 服务端 DESC：最新在前
                return stride(from: anchor - 1, through: anchor - count, by: -1).map {
                    Message(id: $0, conversationId: 7, senderId: 20, body: "m-\($0)",
                            messageType: "text", mediaUrl: nil,
                            createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                            clientTempId: nil)
                }
            case .after, .none:
                return []   // load 里的 refetch（after=100）直接空
            }
        }
        func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message { fatalError() }
        func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
    }

    let conversation = Conversation(
        id: 7, createdAt: Date(),
        peer: makePeer(),
        lastMessageBody: "m-100", lastMessageType: "text", lastMessageSenderId: 20,
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100),
        lastReadMessageId: 100, unreadCount: 0
    )
    let repo = RecordingRepo()
    let vm = ChatViewModel(
        route: .conversation(conversation),
        currentUserId: 10,
        messageRepo: repo,
        wsClient: nil,
        conversationRepository: nil,
        messageStore: messageStore,
        metaStore: metaStore,
        tokenProvider: { "t" }
    )
    await vm.load()      // 渲染 51..100；refetch after=100 空返回

    await vm.loadOlder() // 本地命中 41..50（10 条），远端补 1..40

    let anchor = await repo.lastBeforeAnchor
    let lim = await repo.lastLimit
    let beforeCalls = await repo.beforeCalls
    #expect(beforeCalls == 1)
    #expect(anchor == 41)
    #expect(lim == 40)                    // 50 - 10
    #expect(vm.messages.count == 100)     // 51..100 + 41..50 + 1..40 = 100
    #expect(vm.messages.first?.message.id == 1)

    let cached = try await messageStore.loadLatest(conversationId: 7, limit: 200)
    #expect(cached.count == 100)          // 原 60 + 补 40
}
```

- [ ] **Step 2：跑失败的测试**

```bash
$TEST -only-testing:EchoIMTests/ChatViewModelCacheTests
```

预期：两个新用例都 FAIL——P3 `loadOlder` 不看缓存、也不会把 `limit` 透出为 `50 - cacheHits`。

- [ ] **Step 3：改 `loadOlder`**

```swift
/// §5.3 上滑段：本地优先 + 远端补缺。
/// 1. 先从 store 读 `id < oldestDisplayed` 的 50 条；
/// 2. 如果返回 N == 50 → 纯本地命中，零网络；
/// 3. 如果 N < 50 → 缺 (50 - N) 条，用 `before=oldestCached&limit=50-N` 补；
///    若远端返回空 → `hasMoreOlder = false`。
func loadOlder() async {
    guard let conversationId, !isLoadingOlder, hasMoreOlder else { return }
    guard let oldestDisplayed = messages.first?.message.id else { return }
    guard let token = tokenProvider() else { return }

    isLoadingOlder = true
    defer { isLoadingOlder = false }

    let pageSize = 50

    // 阶段 1：本地
    var localBatch: [Message] = []
    if let messageStore {
        localBatch = (try? await messageStore.loadOlder(
            conversationId: conversationId,
            before: oldestDisplayed,
            limit: pageSize
        )) ?? []
        if !localBatch.isEmpty {
            // loadOlder 返回 DESC；插入时翻成 ASC
            let asc = localBatch.reversed().map(LocalMessage.confirmed)
            messages.insert(contentsOf: asc, at: 0)
        }
    }

    if localBatch.count == pageSize {
        // 本地够用
        return
    }

    // 阶段 2：远端补缺
    let need = pageSize - localBatch.count
    var oldestCached = messages.first?.message.id ?? oldestDisplayed
    if let metaStore,
       let meta = try? await metaStore.load(conversationId: conversationId),
       let oldest = meta.oldestCachedMessageId {
        // 远端补缺必须从缓存下边界往前要，不能用当前展示下边界。
        oldestCached = oldest
    }

    do {
        let rows = try await messageRepo.list(
            conversationId: conversationId,
            cursor: .before(oldestCached),
            limit: need,
            token: token
        )
        if rows.isEmpty {
            hasMoreOlder = false
            return
        }
        // rows DESC；翻成 ASC 插到最前
        let asc = rows.reversed().map(LocalMessage.confirmed)
        messages.insert(contentsOf: asc, at: 0)
        await writeThroughAndMeta(rows)
        if rows.count < need {
            hasMoreOlder = false
        }
    } catch {
        // 远端失败不打断当前渲染；用户下次触顶再试
    }
}
```

- [ ] **Step 4：跑测试**

```bash
$TEST -only-testing:EchoIMTests/ChatViewModelCacheTests
```

预期：两条新用例通过；P3 既有 `ChatViewModelLoadTests` 里 `loadOlder` 的原有断言（基于 `messages.first?.id` + 服务端默认 50）仍通过，因为 store 为 nil 时 `localBatch.isEmpty`，直接走阶段 2 与 P3 行为等价（唯一差别：`limit = 50 - 0 = 50` 显式传入；服务端支持 limit 后与默认行为一致）。

如果 P3 里的 mock repo 没 expect `limit` 字段，加一个 wildcard（`_ limit:`）就行。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
        ios-app/EchoIMTests/ChatViewModelCacheTests.swift
git commit -m "feat(ios): loadOlder reads local cache first, supplements missing count from remote"
```

---

### Task 13：Me 页"清除聊天缓存"按钮

**Files:**
- Modify: `ios-app/EchoIM/Features/Me/MeView.swift:36-50`
- Create: `ios-app/EchoIMUITests/ClearCacheSmokeTests.swift`

- [ ] **Step 1：改 MeView 加按钮**

在登出按钮之前插入一个新 `Section`：

```swift
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
```

在 `MeView` 顶部加状态 + confirmDialog：

```swift
struct MeView: View {
    let container: AppContainer
    var onLogout: () async -> Void

    @State private var showClearCacheConfirm = false
    @State private var isClearing = false

    var body: some View {
        NavigationStack {
            // ... 原 Form 体 ...
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
                ProgressView("清除中…").padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    // ...
}
```

（`container.clearChatCache()` 已在 Task 7 实现。）

- [ ] **Step 2：编译**

```bash
$BUILD
```

预期：编译通过。

- [ ] **Step 3：UI smoke**

创建 `ios-app/EchoIMUITests/ClearCacheSmokeTests.swift`：

```swift
import XCTest

final class ClearCacheSmokeTests: XCTestCase {
    func testClearCacheFromMeTabDoesNotCrash() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset-keychain"]
        app.launch()

        // 走 LoginSmokeTests 的登录流程（复用 smoke 账号）
        let email = app.textFields["loginEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("smoke@test.local")
        let password = app.secureTextFields["loginPassword"]
        password.tap()
        password.typeText("password123")
        app.buttons["loginSubmit"].tap()

        // 切到 Me tab
        let meTab = app.tabBars.buttons["我"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 10))
        meTab.tap()

        // 点清除缓存
        let clearBtn = app.buttons["meClearCache"]
        XCTAssertTrue(clearBtn.waitForExistence(timeout: 5))
        clearBtn.tap()

        // 在 confirmationDialog 里点"清除"
        let confirm = app.buttons["清除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        // 回到聊天 tab，会话列表仍可见（不崩）
        let chatsTab = app.tabBars.buttons["聊天"]
        chatsTab.tap()
        let convList = app.descendants(matching: .any)["conversationsList"]
        XCTAssertTrue(convList.waitForExistence(timeout: 10))
    }
}
```

- [ ] **Step 4：跑 smoke**

```bash
$UITEST -only-testing:EchoIMUITests/ClearCacheSmokeTests
```

预期：绿。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Features/Me/MeView.swift \
        ios-app/EchoIMUITests/ClearCacheSmokeTests.swift
git commit -m "feat(ios): Me tab clear-chat-cache button with confirm dialog"
```

---

### Task 14：收尾 — README + 全量测试 + 手工清单

**Files:**
- Modify: `ios-app/README.md`

- [ ] **Step 1：更新 README**

编辑 `ios-app/README.md` 的 `## Status` 块，把 P4 加进去：

```markdown
## Status
- P1 done: scaffold + login/register/home.
- P2 done: main TabView (Chats / Contacts / Me), friends list, friend requests, user search, conversation list with unread badges, avatar caching via Nuke.
- P3 done: text messaging + real-time WebSocket (ChatView, optimistic send with clientTempId merge, retry on failure, older pagination, mark-as-read, reconnect + heartbeat, ChatsList live updates).
- P4 done: SwiftData cache (per-user ModelContainer under `applicationSupport/EchoIM/users/<id>/`), continuous-suffix invariant (scenario A/B/C), loadOlder local-first, UserSession separation with three-phase tearDown, Me tab clear-chat-cache.
- P5-P8 tracked in `docs/superpowers/specs/2026-04-17-ios-app-design.md` §8.
```

- [ ] **Step 2：服务端 + iOS 全量回归**

```bash
$SLINT
$STEST
$BUILD
$TEST
$UITEST
```

全绿是唯一合格线。

- [ ] **Step 3：最终提交**

```bash
git add ios-app/README.md
git commit -m "docs: note iOS P4 cache + UserSession completion"
```

---

## 模拟器联调清单（P4 全流程验收，跑完 14 项 task 后必做）

后端 + 两个账号 A、B 互为好友。两台设备（或一台 + Web）分别登 A、B。

### 冷启动 / 杀 App 再进

- [ ] 新账号 A 首次登录 → 会话列表空 → 开一个和 B 的会话 → 发 5 条消息 → 杀 App（上滑从 App Switcher 杀）
- [ ] 启动 App → **飞行模式开启** → 登录状态自恢复 → 聊天 tab 秒开会话列表（来自 meta 缓存）
- [ ] 点进和 B 的会话 → 5 条消息立即可见（来自 MessageStore 缓存），**不等网络**
- [ ] 飞行模式关闭 → ChatView 顶部 WS 重连 → `connection.ready` 后场景 C 循环翻页拉回离线期间 B 发的消息（如果 B 真的发了）

### 连续后缀不变式

- [ ] A 的会话 X 当前缓存 id 100..149（50 条）；A 杀 App，B 此期间发 20 条（id 150..169）
- [ ] A 再启动 → 场景 B：`after=149` 拉回 id 150..169 → 缓存变 100..169
- [ ] A 上滑历史 → `loadOlder` 先读本地 id 50..99（若存在）；本地不够时 `before=100&limit=?` 补
- [ ] 多次上滑触顶 → 服务端返回空 → `hasMoreOlder = false`、"加载更多"按钮消失

### 多账号隔离

- [ ] A 登录后生成缓存目录 `applicationSupport/EchoIM/users/<A.id>/cache.sqlite`（Finder / Xcode 里可见）
- [ ] A 登出 → 目录被删（`AppContainer.tearDownSession` 阶段 3）
- [ ] B 登录 → 生成 `applicationSupport/EchoIM/users/<B.id>/cache.sqlite`
- [ ] B 的会话列表 / 消息完全看不到 A 的数据

### JWT 失效路径

- [ ] 手动把 Keychain 改成无效 token → 冷启动 → WS upgrade 401 → `handleUnauthorized` → 三阶段 tearDown（Nuke 清 + session nil + 目录删）→ 回 LoginView

### 清除聊天缓存

- [ ] Me tab → "清除聊天缓存" → 确认弹窗 → 清除完成
- [ ] 确认 `applicationSupport/EchoIM/users/<id>/` 存在（session 未被销毁，目录没删），但 `cache.sqlite-wal` / `cache.sqlite-shm` 里的行已空（可用 `sqlite3` 打开验证 `SELECT COUNT(*) FROM ZCACHEDMESSAGE;` = 0）
- [ ] 再进 ChatView → 场景 A 全量重拉 → 行为无异常
- [ ] 用户没被登出（Me tab 名字 / 头像仍在）

### 场景 C 安全阀

- [ ] 人为在数据库插入大量消息（例如 1500 条全新的 B → A 消息），模拟"离线很久"
- [ ] 客户端重连 → `refetchMissedMessages` 在 20 页（1000 条）处停止；剩余 500 条新消息靠下一次 `connection.ready` / 重新进入聊天页继续从 `newestCachedMessageId` 往后追
- [ ] Console 没有 crash；消息列表连续性保持（不出现 gap）

---

## Self-Review（完成前必过）

- [ ] **P4 覆盖设计 §8 的全部要点**：
  - `@Model CachedMessage` + `@Model ConversationMeta` → Task 3
  - 缓存落盘在 `.applicationSupport` + 排除备份 → Task 6（`UserSession.init`）
  - `ChatViewModel` 改造为 §5.2 连续后缀不变式 → Task 10（write-through）+ Task 11（场景 C 循环）+ Task 12（loadOlder 本地优先）
  - `ConversationListViewModel` 先读 meta 再刷新 → Task 9
  - Me 页"清除聊天缓存"按钮 → Task 13
  - §11.1 服务端 `?limit=` 参数 → Task 1
  - 设计 §2.2 `UserSession` 拆出 → Task 6
  - 设计 §5.5 三阶段 tearDown → Task 7

- [ ] **Placeholder 扫描**：
  `grep -rn -iE "t[b]d|t[o]do|implement[ -]later|similar[ -]to[ -]task" docs/superpowers/plans/2026-04-22-ios-p4-swiftdata-cache.md` 应为空。

- [ ] **类型一致性**（跨任务用到的符号必须自洽）：
  - `MessageRepository.list(conversationId:cursor:limit:token:)` — Task 2 引入，Task 10 / 11 / 12 使用
  - `MessageStore.append(_:)` / `loadLatest(conversationId:limit:)` / `loadOlder(conversationId:before:limit:)` / `deleteAll()` — Task 4 引入，Task 10 / 11 / 12 / 13 使用
  - `ConversationMetaStore.upsert(_:)` / `load(conversationId:)` / `loadAll()` / `deleteAll()` — Task 5 引入，Task 9 / 10 / 11 / 12 / 13 使用
  - `ConversationMetaSnapshot(conversationId:peerUserId:peerUsername:peerDisplayName:peerAvatarUrl:oldestCachedMessageId:newestCachedMessageId:lastReadMessageId:unreadCount:lastMessageBody:lastMessageType:lastMessageAt:)` — Task 3 定义；12 个字段且顺序一致
  - `UserSession.init(userId:apiClient:tokenLoader:onUnauthorized:)` — Task 6 定义，Task 7 使用
  - `UserSession.messageStore()` / `conversationMetaStore()` / `makeMessageRepository()` / `makeConversationRepository()` — Task 6 定义，Task 8 使用
  - `AppContainer.session: UserSession?` — Task 7 定义，Task 8 在 RootView / MainTabView 使用
  - `AppContainer.clearChatCache()` — Task 7 定义，Task 13 使用
  - `ChatView.init(route:currentUserId:messageRepo:messageStore:metaStore:wsClient:conversationRepository:tokenProvider:)` — Task 10 定义，Task 8（MainTabView）+ Task 9（ConversationsListView.destination）使用
  - `ConversationsListView.init(repository:messageRepo:metaStore:messageStore:wsClient:currentUserId:tokenProvider:)` — Task 9 定义，Task 8 使用
  - `ChatViewModel.refetchMissedMessages()` / `writeThroughAndMeta(_:)` — Task 10 / 11 使用，对外可见性 `internal`

- [ ] **`Conversation` / `UserProfile` memberwise init**：
  Task 9 / 10 / 11 / 12 的测试里直接 `Conversation(id:...)` / `UserProfile(id:...)`。这两个类型的 `Decodable.init(from:)` 实现在 **extension** 里（见 `Core/Networking/Models/Conversation.swift:17` `extension Conversation: Decodable`），不会抑制 struct 自动合成的 `internal` memberwise init——测试代码按字段顺序直接构造即可，无需额外加 init。
  确认命令：
  ```bash
  grep -nE "^\s+init\(" ios-app/EchoIM/Core/Networking/Models/Conversation.swift
  grep -nE "^\s+init\(" ios-app/EchoIM/Core/Networking/Models/UserProfile.swift
  ```
  两者 struct 主体里都不应出现显式 init。

- [ ] **Mock repo 的 `list` 签名同步**：
  P3 测试里所有 mock 都是 `list(conversationId:cursor:token:)`，Task 2 Step 4 / Task 10 Step 5 必须全量替换为 `list(conversationId:cursor:limit:token:)`。遗漏会编译失败。
  验证：`grep -rn "func list(conversationId:" ios-app/EchoIMTests` 的每一行都要含 `limit:`。

- [ ] **三阶段 tearDown 的顺序**：
  Task 7 的 `tearDownSession` 必须按 "Nuke → session nil → yield → 删目录"，顺序调换会：
  - Nuke 先 → 放 session 时 ModelContainer 还在写 WAL（无害，WAL 会被关闭时 checkpoint）
  - 先删目录 → SwiftData 文件句柄还持有 → 目录删除可能成功但 WAL 会被重写回来（Apple 的 SQLite 会 rewrite on fsync），下一次启动 schema 可能不一致
  严格按 §5.5 的顺序写。

- [ ] **write-through 不写 pending 消息**：
  `mergeServerResult` 用 `writeThroughAndMeta([message])` 时，`message` 一定是服务端回包 / WS echo 中的 confirmed 消息（非 pending 占位）。`sendText` 的 optimistic insert **不调用** `writeThroughAndMeta`（因为 `Message.id` 是负数占位，落盘后会污染缓存）。
  Task 10 Step 3 的代码里，`handleIncomingMessage` / `mergeServerResult` 都只对 confirmed 消息调 write-through；`sendText` 的 optimistic 路径里**没有**写 store——这一点在 Self-Review 时必须核对。

- [ ] **`ChatsList` WS 增量不写 store**：
  Task 9 的 `ConversationsListViewModel.applyIncomingMessage` 只改内存 `conversations[index]`，**不** upsert meta。理由在计划 "已知妥协" 里；下一次 `refresh()` 兜底写盘。确认 Task 10 代码里没有把 `applyIncomingMessage` 改成写 meta。

- [ ] **`bootstrap()` 不等网络就建 session**：
  Task 7 的 `bootstrap()` 在冷启动发现有 token 时同步调用 `bootstrapSession(userId:)`——这样 `RootView.task { container.connectWebSocketIfNeeded() }` 里的 `container.session?` 一定非 nil。如果 P4 调整让 `bootstrap` 变成 async，需要相应修 RootView 的调用路径（现在 P3 的 `bootstrap()` 是同步，保持。

- [ ] **不变式：`oldestCachedMessageId ≤ oldestDisplayedMessageId` 且 `newestCachedMessageId ≥ newestDisplayedMessageId`**：
  Task 10/11/12 的 write-through 每次都在 `writeThroughAndMeta` 里 `min(existing.oldest, rows.min)` / `max(existing.newest, rows.max)` 单调推进，不会出现 meta 和 messages 反着漂的情况。

- [ ] **已知限制显式记录**：`20 页安全阀触顶`、`SwiftData 写入 best-effort`、`meta 过时未读数`、`清缓存不触发登出` 都在计划文件顶部"已知妥协"段中。

- [ ] **工作目录一致**：所有路径都以 `server/` 或 `ios-app/EchoIM/...` 开头，无裸相对路径。

- [ ] **Lint**：修改 server 代码后 `$SLINT` 必须通过（Task 1 Step 5 已要求）。

---

## 未来阶段的依赖锚点（给 P5+ 计划起草人）

**P5 会触及本阶段的文件**：
- `ChatViewModel.sendImage`（新增）会复用 `writeThroughAndMeta` 落盘——image 消息一旦服务端确认，也要进 `CachedMessage.mediaUrl`。
- `LocalMessage.localImageData` 本阶段保留原状，P5 上才真正填入。
- `CachedMessage.mediaUrl` 字段在 P4 已经有槽位，P5 无需加字段（但可能加 `imageWidth` / `imageHeight` 辅助渲染——那是 schema migration 首次演练）。

**P6 会触及本阶段的文件**：
- `ChatViewModel.handleWSEvent` 的 `default:` 分支继续打开 `typing.*` 处理。`PresenceStore` / `TypingStore` 挂在 `UserSession`（Task 6 已预留扩展空间）。
- `ConversationsListViewModel` 的 WS 增量写 meta 仍由后续 `refresh()` 兜底，不在 P6 引入"每条 WS 写一次盘"——WS 风暴下的写放大交给 P8 做 profile + 优化。

**P7 会触及本阶段的文件**：
- `AppContainer.currentUser` 的 `avatarUrl` 变更时，`ConversationMeta` / `CachedMessage` 不受影响（消息不存 peer）；仅 `Conversation.peer.avatarUrl` 需要在 `refresh()` 后覆盖 meta 的 "last avatar"——但 meta 没存 peer 信息，所以 P7 不需要改 P4 的 store schema。

**P4 引入的设计债**：
- **fire-and-forget write-through 的错误观测**：`try? await store.append(...)` 一旦失败，当前仅 `try?` 吞掉。P8 "打磨 + 测试" 应接入日志框架把 `try?` 改成 `do/catch` + warn。
- **`ConversationMetaSnapshot.upsert` 的部分字段更新**：Task 9 / 10 / 11 / 12 里都手动 merge 老 meta + 新字段，样板略多。P4 完成后如果样板变成维护负担，可在 `ConversationMetaStore` 侧暴露一个 `update(conversationId:mutating:)` helper（传 closure 内部 in-place 改）。当前范围为了最小改动先不做。
- **Schema migration 未演练**：P5 首次加字段（例如 image width/height）时，需要引入 `VersionedSchema` + `SchemaMigrationPlan`——留给 P5 当独立任务。
