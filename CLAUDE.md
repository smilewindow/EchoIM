# CLAUDE.md

本文件为 Claude Code（claude.ai/code）在此代码库中工作时提供指导。

## 项目概述

EchoIM 是一款实时一对一聊天应用（作品集项目）。Monorepo 结构：`/server`（Fastify/Node.js）、`/client`（React + Vite + TypeScript Web 端）、`/ios-app`（SwiftUI iOS 端，刚起步）。通过 Docker Compose 使用 PostgreSQL + Redis，实时通信基于 WebSocket。

**当前状态：** 服务端 12 个阶段全部完成（含多实例扇出、Redis 在线状态租约、图片消息）。Web 客户端已实现至图片消息 + i18n 国际化。iOS 客户端处于脚手架阶段，正在规划实现。剩余工作见 `tasks.md`。

## 仓库结构

```
/server                 Fastify 后端（已完成）
/client                 React + Vite + TypeScript Web 端（已完成）
/ios-app                SwiftUI iOS 端（刚起步）
/e2e                    Playwright 端到端测试（Web）
/docs                   设计规格与文档
docker-compose.yml
prd.md                  完整产品需求文档
tasks.md                12 阶段任务分解与依赖关系图
```

## 命令

```bash
# 启动所有服务（Postgres + Redis + server + client；多实例用 --profile multi）
docker compose up

# 服务端开发（在 /server 目录下）
npm run dev

# Web 客户端开发（在 /client 目录下）
npm run dev

# 代码检查（两个包）
npm run lint
```

**服务端集成测试**（Vitest + 真实 PostgreSQL，`TEST_DATABASE_URL`；每个测试套件在 `beforeEach` 中 `truncateAll()`）：

```bash
npm test --prefix server
```

**E2E 测试**（Playwright，位于根目录 `/e2e`，覆盖认证、聊天实时、Tab 持久化等）：

```bash
npm run test:e2e           # 无头
npm run test:e2e:headed    # 带浏览器窗口
npm run test:e2e:ui        # Playwright UI 模式
```

Web 客户端**无单元测试运行器**，覆盖率依赖 E2E。iOS 客户端用 Swift Testing + XCUITest（规划中）。

修改任何服务端源文件后，在认为任务完成前必须运行 lint：

```bash
npm run lint --prefix server
```

## 架构

### 后端（`/server`）
- **框架：** Fastify，带有 `authenticate` 钩子（JWT 验证，将 `req.user` 附加到请求）
- **数据库：** 通过 `pg` 使用 PostgreSQL；原生 SQL 迁移（无 ORM）
- **WebSocket：** `ws` 库；Fastify 在 `WS /ws?token=<jwt>` 处理升级
- **在线状态：** Redis Sorted Set 租约模型（跨实例），本地 `Map<userId, Set<WebSocket>>` 做投递索引
- **消息扇出：** `broadcast(userId, event)` 通过 Redis Pub/Sub 发布到 `user:{userId}` 频道，所有实例的本地投递器接收并转发给本地 WebSocket
- **连接握手：** 服务端完成 Redis SUBSCRIBE 后发送 `connection.ready`，客户端收到后才标记连接可用

### Web 客户端（`/client`）
- **状态管理：** Zustand stores —— `auth`（JWT + 当前用户）、`chat`（会话/消息/未读聚合）、`friendRequests`、`presence`、`sound`
- **路由：** React Router — `/login`、`/register`、`/`（HomePage，受保护）、`/profile`
- **UI 库：** shadcn/ui + TailwindCSS 4，Lucide 图标
- **国际化：** i18next + react-i18next + 浏览器语言检测，语言包在 `src/locales/`
- **实时：** `useWebSocket` 钩子管理 WS 连接生命周期与重连
- **乐观 UI：** 消息发送时生成 `client_temp_id` 立刻追加为 `pending`；收到 201 或 WS 回声后按 `client_temp_id` 合并；失败显示 `failed` + 重试按钮
- **图片消息：** 两步上传——先 `POST /api/upload/message-image` 获取 `media_url`，再 `POST /api/messages` 带 `media_url` 发送
- **未读数：** 服务端根据 `conversation_members.last_read_message_id` 计算，随 `GET /api/conversations` 的 `unread_count` 字段返回

### iOS 客户端（`/ios-app`）
尚在脚手架阶段。技术栈规划：SwiftUI + iOS 17+（`@Observable`）+ MVVM + URLSession/`URLSessionWebSocketTask` + SwiftData（轻量缓存）+ Nuke（图片磁盘缓存）+ KeychainAccess。见 `docs/superpowers/specs/` 下的设计文档。

### 数据模型
五张表（所有业务 ID 都是 PostgreSQL `SERIAL`/整数，不是 UUID）：
- **`users`**：`id`、`username`、`email`、`password_hash`、`display_name`、`avatar_url`
- **`friend_requests`**：`id`、`sender_id`、`recipient_id`、`status`（`pending`/`accepted`/`declined`）；好友关系由 `status='accepted'` 的记录决定，**无单独的好友表**
- **`conversations`**：`id`、`created_at`
- **`conversation_members`**：`(conversation_id, user_id)` 复合主键，`last_read_message_id INTEGER NULLABLE`（已读游标，严格单调递增）
- **`messages`**：`id`、`conversation_id`、`sender_id`、`body TEXT NULLABLE`、`message_type VARCHAR(20)`（`'text'` / `'image'`）、`media_url TEXT NULLABLE`、`created_at`；DB CHECK 约束保证 `text` 必填 `body`、`image` 必填 `media_url`

`client_temp_id`（客户端生成字符串，用于乐观发送去重）**不持久化**，仅在 `POST /api/messages` 响应和发给发送者本人的 WS 广播中回传。

### WebSocket 事件
| 事件 | 方向 | 备注 |
|------|------|------|
| `connection.ready` | 服务端 → 客户端 | Redis SUBSCRIBE 完成后发送，客户端收到后才视为连接可用 |
| `message.new` | 服务端 → 客户端 | 完整消息对象；**仅发给发送者自己**的那条 payload 额外带 `client_temp_id`，用于多端乐观消息对齐（另一端没有） |
| `conversation.updated` | 服务端 → **自己** | 已读游标更新后仅广播给自己（多设备同步），**不广播给对方**（因此无"对方已读"UI） |
| `typing.start` / `typing.stop` | 客户端 ↔ 服务端 ↔ 接收方 | 转发给会话内另一位成员 |
| `presence.online` / `presence.offline` | 服务端 → 好友 | 进入/离线时只广播给当前在线的好友；包含 Redis Sorted Set 租约 + 30s 心跳 + sweep 定时回收离线幽灵连接 |

## 本地验证

WS / presence / 消息广播 / 跨实例分布等**连接生命周期相关**的行为验证，应该用前端的 **prod build（Vite preview，端口 4173）**，不要用 dev server（端口 5173）：

```bash
npm run build --prefix client
npm run preview --prefix client   # 访问 http://localhost:4173
```

**原因：** `client/src/main.tsx` 启用了 `<StrictMode>`。React 18 在 dev 模式下会把 `useEffect` 双调用（mount → cleanup → mount），`useWebSocket` 每次初始化都会产生一个短命的"影子"WS 连接（典型存活 2 ms 就被 cleanup 关掉）。日志里会看到**每次刷新都有一条多余的 connect + disconnect**，在多实例场景下还会被 nginx 轮询到另一个实例，把"哪条 WS 真的活着、在哪个实例上"变得极难判读。prod build 没有 StrictMode 双调用，日志干净。

**适用场景：**
- 阶段 7 多实例手工验证（`docker compose --profile multi up`）
- 任何要看 `server/src/plugins/ws.ts` 里 `ws connected` / `ws disconnected` 日志来推断行为的调试
- 任何要对比"连接分布在哪个实例"的场景

**日常功能开发不要关 StrictMode**——它是帮你发现 effect 清理 bug 的开发辅助，只是**验证时**切到 prod build 跑一遍。

## 关键决策

- **联系人双向互认：** 用户不能向非好友发消息；好友关系需双方同意
- **JWT 存于 localStorage（Web）/ Keychain（iOS）+ WS token 作为查询参数：** 作品集范围接受 XSS 风险
- **基于游标的分页：** 每页 50 条消息，游标 = 最旧消息的 `id`（整数），通过 `?before=<id>` / `?after=<id>` 传递。SQL 直接 `WHERE id < $2 ORDER BY id DESC LIMIT 50`；不用 timestamp 是因为它无法解决同毫秒多条消息的边界重/漏问题
- **对话自动创建：** 两个好友首次发消息时自动创建（`POST /api/messages`，用 PostgreSQL advisory lock 防止并发下重复建）
- **乐观发送去重：** `client_temp_id` 由客户端生成，服务端原样回传给发送者（REST 响应 + WS 回声），不持久化；客户端以此为 key 合并 pending → sent，幂等
- **图片消息两步上传：** `POST /api/upload/message-image`（服务端用 sharp 压缩到 1600px / JPEG 质量 80）→ 拿到 `media_url` → `POST /api/messages` 带上

# Output Language

Always respond in Chinese

## 