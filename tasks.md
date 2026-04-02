# EchoIM — 任务分解

每个任务足够小，可在单次会话中完成。同一阶段内的任务按依赖顺序排列——从上到下依次完成。完成后标记 `[x]`。
当前建议日常开发基于 `dev` 分支进行，并通过 PR 合并到 `main`。

**状态说明：** `[ ]` 待完成 · `[x]` 已完成 · `[-]` 已跳过

---

## 第 1 阶段 — 项目脚手架

- [x] **1.1** 初始化 Monorepo 结构：`/server`（Fastify）和 `/client`（React + Vite + TS）
- [x] **1.2** 配置 `server`：安装 Fastify、`pg`、`bcrypt`、`jsonwebtoken`、`ws`、`dotenv`
- [x] **1.3** 配置 `client`：安装 TailwindCSS、shadcn/ui、React Router
- [x] **1.4** 编写 `docker-compose.yml`，包含 `postgres` 服务和环境变量；确认 `pg` 连接正常
- [x] **1.5** 为两个包添加 `eslint` + `prettier` 配置；确认 lint 通过

---

## 第 2 阶段 — 数据库 Schema

- [x] **2.1** 编写迁移：`users` 表（`id`、`username`、`email`、`password_hash`、`display_name`、`avatar_url`、`created_at`）
- [x] **2.2** 编写迁移：`friend_requests` 表（`id`、`sender_id`、`recipient_id`、`status`、`created_at`、`updated_at`）
- [x] **2.3** 编写迁移：`conversations` + `conversation_members` 表（含 `last_read_at`）
- [x] **2.4** 编写迁移：`messages` 表
- [x] **2.5** 添加数据库索引：`messages(conversation_id, created_at)`、`friend_requests(recipient_id, status)`

---

## 第 3 阶段 — 认证 API

- [x] **3.1** `POST /api/auth/register` — 验证输入，哈希密码（bcrypt cost 12），插入用户，返回 JWT
- [x] **3.2** `POST /api/auth/login` — 验证凭据，返回 JWT
- [x] **3.3** 编写 `authenticate` Fastify 钩子，验证 JWT 并附加 `req.user`
- [x] **3.4** `GET /api/users/me` — 返回当前用户资料（受保护）
- [x] **3.5** `PUT /api/users/me` — 更新 `display_name` 和 `avatar_url`（受保护）
- [x] **3.6** Vitest 集成测试（22 个用例）：注册、登录、认证错误、资料获取/更新 — 替代纯手工方式；开发期间已完成 curl 冒烟测试

> **测试基础设施在此引入。** Vitest + 真实测试数据库（`TEST_DATABASE_URL`）。关键辅助函数在 `server/tests/helpers/` 中：`buildApp()`（启动 Fastify 实例）、`truncateAll()`（测试间重置数据库）、`registerUser()`（快速注册种子数据）。在 `/server` 目录下运行 `npm test`。后续所有后端阶段遵循相同模式。

---

## 第 4 阶段 — 用户搜索与好友请求 API

- [x] **4.1** `GET /api/users/search?q=` — 对 `username` 做大小写不敏感的模糊匹配，排除自身
- [x] **4.2** `POST /api/friend-requests` — 创建待处理请求；拒绝重复请求或已有反向请求
- [x] **4.3** `GET /api/friend-requests` — 返回当前用户收到的待处理请求
- [x] **4.4** `PUT /api/friend-requests/:id` — 接受或拒绝；接受时无需额外操作（好友关系通过查询 `friend_requests` 中 status=accepted 的记录获取）
- [x] **4.5** `GET /api/friends` — 返回所有存在双向已接受请求的用户
- [x] **4.6** 手工测试：两个用户，发送请求，接受，验证好友列表
- [x] **4.7** 编写集成测试：用户搜索、发送/接受/拒绝好友请求、好友列表、重复请求和自我请求的拒绝

---

## 第 5 阶段 — 对话与消息 REST API

- [x] **5.1** `POST /api/messages` — 接受 `{ recipient_id, body }`；验证好友关系；若无对话则自动创建；插入消息；返回消息对象
- [x] **5.2** `GET /api/conversations` — 列出当前用户的对话，按最新消息排序，含未读数（`last_read_at` 之后的消息）
- [x] **5.3** `GET /api/conversations/:id/messages?before=<cursor>` — 分页历史记录（每页 50 条，游标 = 最旧消息的 `id`）
- [x] **5.4** `PUT /api/conversations/:id/read` — 将当前用户的 `last_read_at` 设为 `NOW()`
- [x] **5.5** 手工测试：发送消息，检查分页，验证已读后未读数减少
- [x] **5.6** 编写集成测试：发送消息（自动创建对话）、含未读数的对话列表、游标分页、已读回执、好友关系校验

---

## 第 6 阶段 — WebSocket 服务端

- [x] **6.1** 在 Fastify 中配置 `WS /ws?token=<jwt>` 端点；升级时进行认证；将连接存入 `Map<userId, Set<WebSocket>>`
- [x] **6.2** 实现 `broadcast(userId, event)` 辅助函数 — 发送给该用户所有活跃会话
- [x] **6.3** `POST /api/messages` 成功后：调用 `broadcast(recipientId, { type: 'message.new', data: message })` 以及发送方其他标签页的广播
- [x] **6.4** `PUT /api/conversations/:id/read` 成功后：向发送方的其他标签页广播 `conversation.updated`
- [x] **6.5** 处理客户端 WS 消息 `typing.start` / `typing.stop` — 转发给接收方的活跃会话
- [x] **6.6** WS 连接时：若用户连接数 ≥ 1，向所有在线好友广播 `presence.online`；同时向新连接者回传已在线好友的快照
- [x] **6.7** WS 断开时：若用户连接数降为 0，向所有在线好友广播 `presence.offline`；防止快速重连时的过期异步结果
- [-] **6.8** 手工测试：两个浏览器标签页，确认实时投递和在线状态事件
- [x] **6.9** 编写集成测试：WS 认证（有效/无效 token）、消息广播、输入事件转发、在线/离线状态、在线状态快照

---

## 第 7 阶段 — 前端：认证页面

- [x] **7.1** 配置 React Router：`/login`、`/register`、`/`（受保护）路由及跳转逻辑
- [x] **7.2** 创建 `authStore`（Zustand 或 React context）：将 JWT 存于 `localStorage`，暴露 `login()`、`logout()`、`user`
- [x] **7.3** 构建 `RegisterPage` — 含用户名、邮箱、密码的表单；调用 `POST /api/auth/register`；成功后跳转至 `/`
- [x] **7.4** 构建 `LoginPage` — 含邮箱、密码的表单；调用 `POST /api/auth/login`；成功后跳转至 `/`
- [x] **7.5** 添加受保护路由包装器 — 未认证用户重定向至 `/login`

---

## 第 8 阶段 — 前端：好友流程

- [x] **8.1** 构建 `UserSearchPanel` — 输入框防抖调用 `GET /api/users/search`；显示结果及"发送请求"按钮
- [x] **8.2** 构建 `FriendRequestsPanel` — 列出待处理的收到请求；接受/拒绝按钮调用 `PUT /api/friend-requests/:id`
- [x] **8.3** 构建 `FriendsList` 组件 — 调用 `GET /api/friends`；显示显示名称 + 在线绿点（暂为占位符）
- [x] **8.4** 接入好友请求角标：挂载时轮询 `GET /api/friend-requests`，若数量 > 0 则显示计数标识

---

## 第 9 阶段 — 前端：聊天视图（仅 REST）

- [x] **9.1** 构建双栏外壳布局：左侧边栏（`FriendsList` + `ConversationList`），右侧面板（`ChatView`）
- [x] **9.2** 构建 `ConversationList` — 调用 `GET /api/conversations`；显示最新消息预览 + 未读角标；按时间倒序排列
- [x] **9.3** 构建 `ChatView` — 加载 `GET /api/conversations/:id/messages`；渲染消息气泡（自己靠右，对方靠左）
- [x] **9.4** 实现无限滚动 / "加载更多消息"按钮，使用游标分页
- [x] **9.5** 构建 `MessageInput` — 文本框，Enter=发送，Shift+Enter=换行；调用 `POST /api/messages`
- [x] **9.6** 乐观消息追加：发送后立即将消息添加到本地列表，标记为 `pending`
- [x] **9.7** 发送失败时：将消息标记为 `failed`，显示重试按钮，重新调用 `POST /api/messages`
- [x] **9.8** 用户打开或聚焦对话时调用 `PUT /api/conversations/:id/read`；本地更新未读数

---

## 第 10 阶段 — 前端：WebSocket 与实时功能

- [x] **10.1** 创建 `useWebSocket` 钩子 — 挂载时连接 `WS /ws?token=<jwt>`，断开后重连，暴露 `onMessage` 回调
- [x] **10.2** 处理 `message.new` 事件 — 若当前对话打开则追加消息；更新对话列表预览 + 未读数
- [x] **10.3** 处理 `conversation.updated` 事件 — 刷新对话列表顺序/预览
- [x] **10.4** 处理 `typing.start` / `typing.stop` — 在 `ChatView` 中显示/隐藏"Alice 正在输入..."提示
- [x] **10.5** 在 `MessageInput` 按键时发送 `typing.start`（防抖）；失焦或 3 秒无活动后发送 `typing.stop`
- [x] **10.6** 处理 `presence.online` / `presence.offline` — 更新 `FriendsList` 和 `ChatView` 头部的在线状态点
- [x] **10.7** 重连时：拉取自上次已知 `created_at` 之后的消息，补全断线期间遗漏的消息
- [x] **10.8** Playwright e2e 测试：认证流程（注册/登录/受保护路由）、聊天冒烟测试（发送消息/对话列表）、实时消息测试（WebSocket 投递/输入提示/在线状态）
- [x] **10.9** 服务端：`POST /api/friend-requests` 和 `PUT /api/friend-requests/:id` 成功后通过 WebSocket 广播 `friend_request.new` / `friend_request.accepted` / `friend_request.declined`；双方（发送方 + 接收方）均收到事件，载荷中包含对方的用户信息（支持多设备场景）
- [x] **10.10** 客户端：创建 `useFriendRequestStore`（Zustand）集中管理好友请求状态（`incoming`、`sent`、`history`、`friendsVersion`）；替代原各组件内的分散 `useState` + `useEffect` 本地状态
- [x] **10.11** 客户端：`useWebSocket` 钩子处理 `friend_request.*` 事件 — 更新 store 并展示 toast 通知；重连时调用 `fetchAll()` 补全离线期间的变更
- [x] **10.12** 客户端：重构 `FriendRequestsPanel`、`FriendsList`、`UserSearchPanel`、`HomePage` 以读取 `useFriendRequestStore`；`FriendsList` 订阅 `friendsVersion` 在好友请求被接受时自动刷新
- [x] **10.13** 服务端集成测试：覆盖所有好友请求 WS 事件（`friend_request.new` / `accepted` / `declined`），验证发送方与接收方视角下的用户信息载荷

> **端到端测试基础设施在此引入。** Playwright + Chromium，配置见 `playwright.config.ts`。测试文件在 `e2e/` 目录下：`auth.spec.ts`（认证流程）、`chat-smoke.spec.ts`（聊天冒烟）、`chat-realtime.spec.ts`（实时功能）。辅助函数在 `e2e/helpers.ts` 中。Playwright 自动启动前后端开发服务器（`webServer` 配置）。在项目根目录下运行 `npx playwright test`。

---

## 第 11 阶段 — 完善与主题

- [x] **11.1** 应用 shadcn/ui 主题变量；全局添加 `dark:` Tailwind 类；确认随系统设置自动切换
- [x] **11.2** 为对话列表和消息历史添加加载骨架屏
- [x] **11.3** 添加空状态：无对话、无好友、无搜索结果
- [x] **11.4** 收到新消息时将聊天面板滚动到底部（用户上翻时除外）
- [x] **11.5** 使用 shadcn/ui `Toast` 为错误添加 toast 通知（登录失败、网络错误等）
- [x] **11.6** 构建 `ProfileEditPage` — 显示名称 + 头像 URL 表单；调用 `PUT /api/users/me`

---

## 第 12 阶段 — 部署

- [x] **12.1** 为后端添加 `Dockerfile`（Node.js）；多阶段构建
- [x] **12.2** 为前端添加 `Dockerfile`（Vite 构建 → nginx 静态服务）
- [x] **12.3** 更新 `docker-compose.yml`，包含三个服务：`postgres`、`server`、`client`
- [x] **12.4** 将所有密钥外置到 `.env` 文件；添加 `.env.example`；确认无硬编码内容
- [x] **12.5** 准备云虚拟机（AWS EC2 / GCP Compute Engine / Azure VM）；安装 Docker + Compose
- [x] **12.6** 部署：在虚拟机上执行 `git pull` + `docker compose up -d`；确认应用可通过公网 IP 访问
- [x] **12.7** 在线上服务器进行端到端冒烟测试：注册两个账号，添加好友，实时聊天

---

## 依赖关系图

```
第 1 阶段（脚手架）
  └─ 第 2 阶段（数据库 Schema）
       └─ 第 3 阶段（认证 API）
            ├─ 第 4 阶段（好友 API）
            │    └─ 第 5 阶段（消息 API）
            │         └─ 第 6 阶段（WebSocket）
            └─ 第 7 阶段（前端认证）
                 └─ 第 8 阶段（前端好友）
                      └─ 第 9 阶段（前端聊天 — REST）
                           └─ 第 10 阶段（前端 — 实时）
                                └─ 第 11 阶段（完善）
                                     └─ 第 12 阶段（部署）
```

> 第 5 阶段完成后，第 6 和第 9 阶段可并行开发。
> 第 11 阶段可与第 9–10 阶段交叉进行。
