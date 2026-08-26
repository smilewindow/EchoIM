# EchoIM

EchoIM 是一个跨平台即时通讯项目，包含 React Web 客户端、Fastify API 服务和
SwiftUI iOS 客户端。项目支持好友关系、单聊、图片消息、已读状态、在线状态、
正在输入提示，以及基于 Redis Pub/Sub 的多实例实时事件同步。

## 功能概览

- 邀请码注册、登录与 JWT 身份认证
- 用户搜索、好友申请与联系人管理
- 一对一文本消息和图片消息
- 会话列表、未读计数与已读游标
- WebSocket 实时消息、在线状态和正在输入提示
- 头像上传、个人资料编辑与图片预览
- Web 中英文切换和 iOS 本地化
- iOS SwiftData 本地缓存、消息发送状态与重连机制
- Redis Pub/Sub 跨服务实例事件分发

## 技术栈

- Web：React 18、TypeScript、Vite、Tailwind CSS、Zustand、i18next
- Server：Fastify、TypeScript、PostgreSQL 16、Redis 7、WebSocket
- iOS：SwiftUI、SwiftData，最低支持 iOS 17
- 测试与质量：ESLint、Vitest、Playwright、GitHub Actions
- 部署：Docker Compose、Nginx

## 项目结构

```text
EchoIM/
├── client/                 # React Web 客户端
├── server/                 # Fastify API、WebSocket 与数据库迁移
├── ios-app/                # SwiftUI iOS 客户端与测试
├── e2e/                    # Playwright 端到端测试
├── docs/                   # 设计文档和实现计划
├── docker-compose.yml      # 本地依赖、单实例和多实例部署
├── playwright.config.ts    # Web E2E 配置
└── .env.example            # 本地环境变量模板
```

## 本地开发

### 环境要求

- Node.js 20+
- npm
- Docker Desktop 或兼容的 Docker Compose 环境
- Xcode 26+（仅 iOS 开发需要）

### 1. 安装依赖

```bash
npm ci
npm ci --prefix client
npm ci --prefix server
```

### 2. 配置环境变量

```bash
cp .env.example .env
```

至少需要设置以下变量：

```dotenv
POSTGRES_PASSWORD=your-local-password
DATABASE_URL=postgresql://echoim:your-local-password@localhost:5432/echoim
JWT_SECRET=replace-with-a-long-random-string
INVITE_CODES=your-invite-code
REDIS_URL=redis://localhost:6379
```

真实密码和密钥只保存在本地，不要提交 `.env`。

### 3. 启动 PostgreSQL 和 Redis

```bash
docker compose up -d postgres redis
```

### 4. 执行数据库迁移

```bash
npm run migrate --prefix server
```

### 5. 启动服务

分别在两个终端运行：

```bash
npm run dev:server
```

```bash
npm run dev:client
```

启动后可访问：

- Web：<http://localhost:5173>
- API：<http://localhost:3000>
- 健康检查：<http://localhost:3000/healthz>

注册时使用 `.env` 中 `INVITE_CODES` 配置的任一邀请码。

## 常用命令

```bash
# 前端检查与构建
npm run lint --prefix client
npm run build --prefix client

# 后端测试、检查与构建
npm run test --prefix server
npm run lint --prefix server
npm run build --prefix server

# Playwright 端到端测试
npm run test:e2e
```

首次运行 Playwright 前需要安装 Chromium：

```bash
npx playwright install chromium
```

E2E 会使用独立的 `echoim_e2e` 数据库，并在本地启动测试服务。运行前请确保
PostgreSQL 和 Redis 可用，且根目录 `.env` 已正确配置。

## Docker 部署

单实例部署：

```bash
docker compose --profile deploy up -d --build
```

多实例与 Redis Pub/Sub 验证：

```bash
docker compose --profile multi up -d --build
```

`server` 容器会在启动 API 前自动执行数据库迁移。生产环境必须替换
`POSTGRES_PASSWORD`、`JWT_SECRET` 和邀请码等默认配置。

## iOS 客户端

使用 Xcode 打开 [ios-app/EchoIM.xcodeproj](ios-app/EchoIM.xcodeproj)，选择 iOS 17+
模拟器或设备运行。默认后端地址和其他 iOS 开发说明见
[ios-app/README.md](ios-app/README.md)。
