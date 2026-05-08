# iOS 日志系统实现计划

## 目标

为 EchoIM iOS 端构建基于 `os.Logger` 的分层日志系统，支持：
- 按子系统分类记录（网络、WebSocket、认证、缓存、UI、应用生命周期）
- 内存环形缓冲 + in-app 查看器（Release 包也可用，隐蔽入口）
- 统一隐私策略，敏感数据可控

## 设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 日志后端 | `os.Logger` + 内存环形缓冲 | 零依赖、性能好、Console.app 集成 |
| 持久化 | 不落文件，仅内存 500 条 | 作品集项目够用，后续可扩展 |
| Release 可用性 | 隐蔽入口（MeView 长按版本号） | 真机不连 Xcode 也能排查 |
| 请求/响应 body | 当前记录（截断 1000 字符） | 用户明确要求，以后需要保密再关 |
| 格式 | `文件名:行号  时间  [分类]  消息` | 用户要求文件名+行号在最前面 |

## 文件结构

```
EchoIM/Core/Logging/
├── LogCategory.swift      — 日志分类枚举（6 个子系统）
├── LogLevel.swift         — 日志级别枚举（4 级，映射 OSLogType）
├── LogEntry.swift         — 单条日志记录 struct
├── LogStore.swift         — @Observable 内存环形缓冲（500 条）
├── Log.swift              — 统一 API（os.Logger + LogStore 双写）
└── LogViewer.swift        — In-app 日志查看器 SwiftUI View
```

## 核心类型设计

### LogCategory

```swift
enum LogCategory: String, CaseIterable {
    case network    // APIClient HTTP 请求/响应
    case ws         // WebSocket 生命周期、事件
    case auth       // 登录/登出/token
    case cache      // SwiftData 读写
    case ui         // 页面导航
    case app        // AppContainer 会话生命周期
}
```

### LogLevel → OSLogType 映射

| Level | OSLogType | 用途 |
|-------|-----------|------|
| debug | .debug | 请求/响应 body 等细节 |
| info | .info | 正常流程关键节点 |
| warning | .default | 异常但可恢复 |
| error | .error | 不可恢复错误 |

### LogEntry

```swift
struct LogEntry: Identifiable {
    let id: UUID          // 自动生成
    let timestamp: Date   // 自动生成
    let level: LogLevel
    let category: LogCategory
    let message: String
    let file: String      // 文件名（不含路径和 .swift 后缀）
    let line: Int
}
```

### Log 统一 API

```swift
// 调用方式 —— file/line 由 #fileID/#line 默认参数自动捕获
Log.info(.network, "→ GET /api/conversations")
Log.debug(.network, "body: {\"conversationId\":3}")
Log.error(.ws, "pong timeout, scheduling reconnect")
```

每次调用做两件事：
1. 写 `os.Logger`（按 category 分实例，subsystem = bundleIdentifier）
2. 追加 `LogStore.shared`（供 in-app 查看器）

非主线程调用时通过 `DispatchQueue.main.async` 安全地写入 LogStore。

### LogStore

- `@Observable` + `@MainActor`
- 容量 500 条，FIFO 淘汰
- 全局单例 `LogStore.shared`

## 日志格式

```
APIClient:92   12:34:56.789  [network]   → POST /api/messages
APIClient:95   12:34:56.790  [network]     body: {"body":"hello","conversationId":3}
APIClient:108  12:34:57.012  [network]   ← 201 POST /api/messages (222ms)
APIClient:110  12:34:57.013  [network]     response: {"id":301,"body":"hello",...}
WebSocketClient:324  12:34:57.015  [ws]  event message.new
```

## 隐私策略

| 数据 | 策略 |
|------|------|
| JWT token | 只打 `Bearer ***` |
| URL path | 完整记录 |
| HTTP 状态码/耗时 | 完整记录 |
| 请求 body | 完整记录，截断 1000 字符 |
| 响应 body | 完整记录，截断 1000 字符 |
| 消息内容 | 跟随 body 记录（当前不脱敏） |
| 用户密码 | 跟随 body 记录（当前不脱敏，后续可加黑名单字段） |

## 接入点（4 处集中埋点）

### 1. APIClient.request() — 一处覆盖所有 JSON 请求

```
→ POST /api/messages                              // info：请求发出
  body: {"body":"hello","conversationId":3}        // debug：请求 body
← 201 POST /api/messages (222ms)                  // info：成功响应
  response: {"id":301,"body":"hello",...}           // debug：响应 body
✗ 401 GET /api/conversations (45ms)                // error：HTTP 错误
✗ network URLError Code=-1009                      // error：网络层错误
✗ decode Response<[Conversation]> ...              // error：解码错误
```

### 2. APIClient.upload() — multipart 上传

```
→ UPLOAD POST /api/upload/message-image (524KB)    // info：上传发出（只记大小，不记 body）
← 200 POST /api/upload/message-image (1832ms)      // info：上传成功
  response: {"mediaUrl":"/uploads/..."}             // debug：响应 body
```

### 3. WebSocketClient — 状态机 + 事件

在以下位置插入 Log 调用（不改 state 设置方式，在赋值旁边加一行 Log）：

| 位置 | 日志 |
|------|------|
| `openSocket()` state=.connecting | `info: connecting to ws://...` |
| `didOpenWithProtocol` state=.handshaking | `info: TCP upgraded, waiting connection.ready` |
| `handleReceivedMessage` state=.ready | `info: connection ready` |
| `handleReceivedMessage` 解码失败 (L342) | `warning: decode error: ...` |
| `scheduleReconnect()` | `warning: reconnecting in {delay}s` |
| `disconnect()` | `info: disconnected (reason)` |
| `sendPingWithTimeout` pong 超时 | `warning: pong timeout` |
| `didCompleteWithError` 401 | `error: 401 unauthorized, stop reconnect` |
| `handleReceivedMessage` 事件分发 | `debug: event {type}` |

### 4. AppContainer + UserSession — 会话生命周期

| 位置 | 日志 |
|------|------|
| `bootstrap()` 恢复登录态 | `info: bootstrap restored userId={id}` |
| `bootstrap()` 无 token | `info: bootstrap no stored token` |
| `handleLoginSuccess()` | `info: login success userId={id}` |
| `handleUnauthorized()` | `warning: unauthorized, tearing down session` |
| `logout()` | `info: logout, tearing down session` |
| `clearChatCache()` | `info: cleared chat cache` |
| UserSession WS 事件路由 | `debug: routing {eventType}` |

## LogViewer UI

### 入口

MeView → 长按版本号文本（≥ 0.5 秒）→ sheet 弹出 LogViewer。

MeView 当前没有版本号文本，需要在 `logoutCard` 下方新增一个版本号 footer：
```swift
Text("EchoIM v\(appVersion)")
    .font(.caption2)
    .foregroundStyle(.secondary)
    .onLongPressGesture(minimumDuration: 0.5) { showLogViewer = true }
```

### 功能

- **Category 筛选：** 横向滚动 chip，可多选/全选切换
- **Level 筛选：** Picker（全部 / warning+ / error only）
- **文本搜索：** SearchBar，实时过滤 message 字段
- **颜色编码：** debug=灰、info=蓝、warning=橙、error=红
- **长按单条：** 复制完整日志文本到剪贴板
- **清除按钮：** toolbar 右上角，清空 LogStore
- **自动滚底：** 新日志进来时 ScrollViewReader 滚到底部

### 单条日志展示格式

```
APIClient:92  12:34:56  [network]
→ POST /api/messages
```

上方一行是 meta（小字灰色），下方是 message（正常字号，颜色按 level）。

## 实现顺序

### Phase 1：基础层（5 个文件）

1. `LogCategory.swift` — 枚举
2. `LogLevel.swift` — 枚举 + OSLogType 映射
3. `LogEntry.swift` — 数据结构
4. `LogStore.swift` — 环形缓冲
5. `Log.swift` — 统一 API

### Phase 2：接入 APIClient（2 个文件修改）

6. `APIClient.swift` — request() 方法内加入口/出口/错误日志
7. `APIClient+Upload.swift` — upload() 方法内加日志（body 只记大小）

### Phase 3：接入 WebSocket（1 个文件修改）

8. `WebSocketClient.swift` — 状态转换 + 事件分发 + 错误处理

### Phase 4：接入会话生命周期（2 个文件修改）

9. `AppContainer.swift` — bootstrap / login / logout / unauthorized
10. `UserSession.swift` — WS 事件路由日志

### Phase 5：LogViewer UI + 入口（2 个文件）

11. `LogViewer.swift` — 新建查看器 View
12. `MeView.swift` — 添加版本号 footer + 长按弹出

### Phase 6：验证

13. Xcode 构建通过
14. 模拟器运行，触发登录 → 聊天 → 登出流程，在 LogViewer 中查看日志输出
