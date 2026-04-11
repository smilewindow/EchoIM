# CLAUDE.md

本文件为 Claude Code（claude.ai/code）在此代码库中工作时提供指导。

## 项目概述

EchoIM 是一款实时一对一聊天应用（作品集项目）。Monorepo 结构，包含 `/server`（Fastify/Node.js）和 `/client`（React + Vite + TypeScript）。通过 Docker Compose 使用 PostgreSQL，实时通信基于 WebSocket。

**当前状态：** 第 1–4 阶段已完成（脚手架、数据库 Schema、认证 API、好友 API）。剩余工作见 `tasks.md`。

## 仓库结构

```
/server       Fastify 后端（已实现第 1–4 阶段）
/client       React + Vite + TypeScript 前端（尚未开始）
docker-compose.yml
prd.md        完整产品需求文档
tasks.md      12 阶段任务分解与依赖关系图
```

## 命令

脚手架搭建完成（第 1 阶段）后，预期使用以下命令：

```bash
# 启动所有服务
docker compose up

# 服务端开发（在 /server 目录下）
npm run dev

# 客户端开发（在 /client 目录下）
npm run dev

# 代码检查（两个包）
npm run lint
```

服务端已配置 Vitest 集成测试。在 `/server` 目录下运行：

```bash
npm test
```

测试使用真实 PostgreSQL 数据库（`TEST_DATABASE_URL`）。每个测试套件在 `beforeEach` 中调用 `truncateAll()`。客户端尚未配置测试运行器。

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

### 前端（`/client`）
- **状态管理：** Zustand `authStore` 持有 JWT（localStorage）和当前用户
- **路由：** React Router — `/login`、`/register`、`/`（受保护）
- **实时：** `useWebSocket` 钩子管理 WS 连接生命周期和重连
- **乐观 UI：** 消息发送后立即追加为 `pending` 状态，出错后更新为 `failed` 并显示重试按钮
- **未读数：** 通过 `conversation_members` 中的 `last_read_at` 在服务端计算

### 数据模型
五张表：`users`、`friend_requests`、`conversations`、`conversation_members`（含 `last_read_at`）、`messages`。好友关系由 `friend_requests` 表中 `status = 'accepted'` 的记录决定，无单独的好友表。

### WebSocket 事件
| 事件 | 方向 | 备注 |
|------|------|------|
| `connection.ready` | 服务端 → 客户端 | Redis SUBSCRIBE 完成后发送，客户端收到后才视为连接可用 |
| `message.new` | 服务端 → 客户端 | 完整消息对象 |
| `conversation.updated` | 服务端 → 客户端 | 已读回执更新后 |
| `typing.start` / `typing.stop` | 客户端 ↔ 服务端 ↔ 接收方 | 转发给接收方会话 |
| `presence.online` / `presence.offline` | 服务端 → 好友 | WS 连接/断开时 |

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
- **JWT 存于 localStorage + WS token 作为查询参数：** 作品集范围接受 XSS 风险
- **基于游标的分页：** 每页 50 条消息，游标 = 最旧消息的 `created_at`
- **对话自动创建：** 两个好友首次发消息时自动创建（`POST /api/messages`）
- **第 6 和第 9 阶段可并行：** 第 5 阶段（消息 REST API）完成后即可同时进行

# Output Language

Always respond in Chinese

## 