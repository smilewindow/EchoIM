# EchoIM — 产品需求文档

**版本：** 1.1（MVP — 面试后整理版）
**日期：** 2026-03-16

---

## 1. 概述

EchoIM 是一款基于浏览器的实时即时通讯应用，作为作品集项目开发。MVP 提供完整的一对一聊天体验：注册账号、发送/接受好友请求，并在多设备间实时收发消息。

---

## 2. 目标

- 以最小范围交付一个可用的实时聊天体验。
- 打造一个精良、可部署的作品集项目，展示全栈工程能力。
- 端到端交付稳定、可云端部署的产品。

---

## 3. MVP 范围外功能

- 群聊 / 频道
- 语音或视频通话
- 文件 / 图片分享（头像仅支持 URL 输入）
- 消息表情反应、话题串或回复
- 推送通知（Web Push / 移动端）
- 消息搜索
- 用户拉黑 / 举报
- 管理后台
- 头像文件上传（仅支持 URL 输入）

---

## 4. 用户故事

### 认证
| ID | 故事 |
|----|------|
| A1 | 作为新用户，我可以用用户名、邮箱和密码注册账号。 |
| A2 | 作为已有账号的用户，我可以用邮箱和密码登录。 |
| A3 | 作为已登录用户，我可以退出登录。 |

### 好友请求
| ID | 故事 |
|----|------|
| F1 | 作为用户，我可以通过用户名搜索其他已注册用户。 |
| F2 | 作为用户，我可以向其他用户发送好友请求。 |
| F3 | 作为用户，我可以接受或拒绝收到的好友请求。 |
| F4 | 作为用户，我可以查看我的好友列表（已接受的联系人）。 |

### 消息
| ID | 故事 |
|----|------|
| M1 | 作为用户，我可以与好友开启一对一对话。 |
| M2 | 作为用户，我可以按 Enter 发送文本消息（Shift+Enter 换行）。 |
| M3 | 作为用户，我可以在所有打开的标签页/设备上实时收到消息。 |
| M4 | 作为用户，我可以翻页浏览历史消息。 |
| M5 | 作为用户，我可以查看最近对话列表及未读数。 |
| M6 | 作为用户，我可以看到好友正在输入的提示。 |
| M7 | 作为用户，我可以看到消息发送失败的提示，并手动重试。 |

### 在线状态
| ID | 故事 |
|----|------|
| PR1 | 作为用户，我可以看到好友当前是否在线。 |

### 个人资料
| ID | 故事 |
|----|------|
| P1 | 作为用户，我可以设置或更新我的显示名称和头像 URL。 |

---

## 5. 功能需求

### 5.1 认证
- 注册：唯一邮箱 + 用户名，密码哈希（bcrypt cost ≥ 12），返回 JWT。
- 登录：邮箱 + 密码，返回 JWT。
- JWT 存储在客户端的 `localStorage`，有效期 7 天。
- 所有受保护的 REST 路由需携带 `Authorization: Bearer <token>`。
- WebSocket 认证：token 作为查询参数 `?token=<jwt>` 传递（对于作品集项目是可接受的权衡；已知会记录在服务器访问日志中）。

### 5.2 好友请求
- 联系人为**双向互认**：用户 A 发起请求，用户 B 必须接受后双方才能互发消息。
- 用户不能向非好友发送消息。
- `friend_requests` 表跟踪 pending/accepted/declined 状态。
- 接受请求后，双方均出现在对方的好友列表中。

### 5.3 对话与消息
- 两个好友发送第一条消息时，系统自动创建对话。
- 消息字段：`id`、`conversation_id`、`sender_id`、`body`、`created_at`。
- 消息通过 WebSocket 实时推送给接收方的**所有活跃会话**（多设备扇出）。
- 重连时，客户端拉取自上次接收的 `created_at` 之后的消息。
- 对话列表按最新消息降序排列，服务端跟踪未读数。
- 消息历史支持分页（基于游标，每页 50 条）。
- 消息发送失败时，界面显示"失败"标识及手动重试按钮。

### 5.4 实时（WebSocket）
- 服务端为每个已认证用户维护一个或多个 WebSocket 连接（多设备支持）。
- 同一用户的所有会话均接收相同的扇出事件。

| 事件 | 方向 | 载荷 |
|------|------|------|
| `message.new` | 服务端 → 客户端 | 完整消息对象 |
| `conversation.updated` | 服务端 → 客户端 | 更新后的对话元数据 |
| `typing.start` | 客户端 → 服务端 → 接收方 | `{ conversation_id }` |
| `typing.stop` | 客户端 → 服务端 → 接收方 | `{ conversation_id }` |
| `presence.online` | 服务端 → 好友 | `{ user_id }` |
| `presence.offline` | 服务端 → 好友 | `{ user_id }` |

### 5.5 在线状态
- 用户至少有一个活跃 WebSocket 连接时为**在线**。
- 所有连接断开时为**离线**。
- 连接/断开时，服务端向所有在线好友广播 `presence.online` / `presence.offline`。

### 5.6 未读数
- `conversation_members` 表有 `last_read_at` 字段。
- 用户打开或聚焦对话时更新为 `NOW()`。
- 未读数 = 该对话中 `created_at > last_read_at` 的消息数。

---

## 6. 非功能需求

| 关注点 | 目标 |
|--------|------|
| 延迟 | 同区域网络消息投递 < 300ms |
| 认证安全 | bcrypt cost ≥ 12；JWT 存于 localStorage（MVP 接受 XSS 风险） |
| API 风格 | CRUD 使用 RESTful JSON；实时事件使用 WebSocket |
| 数据持久化 | PostgreSQL（Docker Compose 自托管于同一虚拟机） |
| 部署 | 通过 Docker Compose 部署到 AWS / GCP / Azure 云虚拟机 |
| 多设备 | 服务端将 WS 事件扇出到该用户所有活跃会话 |
| 主题 | 跟随系统偏好（通过 CSS `prefers-color-scheme` 自动切换亮/暗色） |

---

## 7. 技术栈

| 层级 | 选型 |
|------|------|
| 前端 | React + TypeScript、TailwindCSS、**shadcn/ui** |
| 后端 | **Node.js（Fastify）** |
| 实时 | WebSocket（`ws` 库） |
| 数据库 | PostgreSQL |
| 认证 | JWT（`jsonwebtoken`） |
| 容器 | Docker Compose |
| 托管 | AWS / GCP / Azure 虚拟机 |

---

## 8. API 接口

### 认证
```
POST /api/auth/register
POST /api/auth/login
```

### 用户
```
GET  /api/users/me
PUT  /api/users/me
GET  /api/users/search?q=<username>
```

### 好友请求
```
GET  /api/friend-requests                  # 待处理的收到请求
POST /api/friend-requests                  { recipient_id }
PUT  /api/friend-requests/:id              { action: "accept" | "decline" }
```

### 好友
```
GET  /api/friends                          # 已接受的好友列表
```

### 对话
```
GET  /api/conversations
GET  /api/conversations/:id/messages?before=<cursor>
PUT  /api/conversations/:id/read           # 更新 last_read_at
```

### 消息
```
POST /api/messages                         { recipient_id, body }
```

### WebSocket
```
WS   /ws?token=<jwt>
```

---

## 9. 数据模型

```
users
  id            UUID PK
  username      VARCHAR(50) UNIQUE NOT NULL
  email         VARCHAR(255) UNIQUE NOT NULL
  password_hash TEXT NOT NULL
  display_name  VARCHAR(100)
  avatar_url    TEXT
  created_at    TIMESTAMPTZ

friend_requests
  id            UUID PK
  sender_id     UUID FK → users.id
  recipient_id  UUID FK → users.id
  status        VARCHAR(10) NOT NULL DEFAULT 'pending'  -- 'pending' | 'accepted' | 'declined'
  created_at    TIMESTAMPTZ
  updated_at    TIMESTAMPTZ
  UNIQUE (sender_id, recipient_id)

conversations
  id            UUID PK
  created_at    TIMESTAMPTZ

conversation_members
  conversation_id  UUID FK → conversations.id
  user_id          UUID FK → users.id
  last_read_at     TIMESTAMPTZ
  PRIMARY KEY (conversation_id, user_id)

messages
  id              UUID PK
  conversation_id UUID FK → conversations.id
  sender_id       UUID FK → users.id
  body            TEXT NOT NULL
  created_at      TIMESTAMPTZ
```

> **注意：** 在线状态在服务端内存中跟踪（`Map<userId, Set<WebSocket>>`），不持久化到数据库。MVP 阶段无需持久化。

---

## 10. UI 页面与布局

### 布局
经典双栏布局（类 Slack / Telegram Web 风格）：
```
+------------------+-----------------------------+
| 好友 / 聊天       |  Alice  🟢 在线             |
|------------------|  Alice 正在输入...           |
| 🟢 Alice  [2] >  |-----------------------------|
| ⚫ Bob            |  [10:01] Alice: 嘿！         |
| 🟢 Carol          |  [10:02] 你: 你好            |
|------------------|                             |
| [搜索用户]        |  [输入框]         [发送]     |
+------------------+-----------------------------+
```

### 页面列表
1. **注册** — 用户名、邮箱、密码 + 提交
2. **登录** — 邮箱、密码 + 提交
3. **对话列表（侧边栏）** — 最近聊天、未读数角标、在线绿点
4. **聊天视图** — 消息历史、正在输入提示、输入框（Enter=发送）、失败重试
5. **好友请求** — 收到的请求列表，含接受 / 拒绝操作
6. **用户搜索** — 搜索栏 + "发送好友请求"操作
7. **个人资料编辑** — 显示名称、头像 URL

### 主题
- 遵循系统 `prefers-color-scheme`（亮色 / 暗色自动切换）。
- 使用 shadcn/ui + Tailwind CSS 变量实现主题。

---

## 11. 里程碑

| # | 里程碑 | 交付物 |
|---|--------|--------|
| M1 | 数据库 Schema + 认证 API | `users` 表、注册/登录接口、JWT |
| M2 | 好友请求系统 | `friend_requests` 表、发送/接受/拒绝 API + WS 事件 |
| M3 | 对话 + 消息 REST API | 分页历史记录、`last_read_at`、未读数 |
| M4 | WebSocket 核心 | 实时消息投递、多设备扇出 |
| M5 | 在线状态 + 输入提示 | `presence.*` 和 `typing.*` WS 事件 |
| M6 | 前端：认证 + 好友流程 | 注册、登录、用户搜索、好友请求 |
| M7 | 前端：聊天视图 | 双栏布局、实时消息、输入提示、重试 UX |
| M8 | 部署 | Docker Compose、云虚拟机、环境配置、冒烟测试 |

---

## 12. 关键决策与权衡

| 决策 | 选择 | 权衡 |
|------|------|------|
| 联系人模型 | 双向好友请求 | 更安全、用户意图明确；增加了 `friend_requests` 表和 API 面 |
| JWT 存储 | localStorage | 更简单；存在 XSS 风险 — 作品集范围可接受 |
| WS 认证 | Token 作为查询参数 | Token 会出现在服务器访问日志中 — 作品集可接受 |
| 在线状态 | 内存 Map | 速度快，零数据库写入；服务重启后丢失（单服务器 MVP 可接受） |
| 多设备 | 全量扇出 | 所有活跃会话均接收事件；服务端使用 `Map<userId, Set<WS>>` |
| 头像 | 仅 URL | MVP 无需 S3 或文件上传逻辑 |
| 数据库托管 | Docker 自托管 | 成本最低；无托管数据库开销；作品集流量足够 |

---

## 13. 成功标准

- 两个用户能注册账号、通过搜索找到对方、发送/接受好友请求，并实时收发消息。
- 消息同时投递给接收方所有打开的标签页。
- 未读数正确更新，刷新页面后保持不变。
- 在线/离线状态实时更新。
- 消息在刷新页面后持久保留。
- 所有 API 接口返回正确的 HTTP 状态码和 JSON 错误体。
- 应用可通过单条 `docker compose up` 命令端到端运行，并部署到云虚拟机。
