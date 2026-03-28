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
- **在线状态：** 内存 `Map<userId, Set<WebSocket>>` — 不持久化，重启后丢失
- **消息扇出：** `broadcast(userId, event)` 发送给该用户所有活跃 WS 会话（多设备支持）

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
| `message.new` | 服务端 → 客户端 | 完整消息对象 |
| `conversation.updated` | 服务端 → 客户端 | 已读回执更新后 |
| `typing.start` / `typing.stop` | 客户端 ↔ 服务端 ↔ 接收方 | 转发给接收方会话 |
| `presence.online` / `presence.offline` | 服务端 → 好友 | WS 连接/断开时 |

## 关键决策

- **联系人双向互认：** 用户不能向非好友发消息；好友关系需双方同意
- **JWT 存于 localStorage + WS token 作为查询参数：** 作品集范围接受 XSS 风险
- **基于游标的分页：** 每页 50 条消息，游标 = 最旧消息的 `created_at`
- **对话自动创建：** 两个好友首次发消息时自动创建（`POST /api/messages`）
- **第 6 和第 9 阶段可并行：** 第 5 阶段（消息 REST API）完成后即可同时进行

# Output Language

Always respond in Chinese

## 