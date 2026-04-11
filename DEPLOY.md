# EchoIM 部署指南

## 前置条件

- 一台云 VM（AWS EC2 / GCP Compute Engine / Azure VM 等），建议 1 vCPU + 1 GB RAM 以上
- VM 安全组/防火墙开放端口：**80**（HTTP）、**22**（SSH）
- 已安装 Docker 和 Docker Compose（v2）

## 1. 安装 Docker（如尚未安装）

```bash
# Ubuntu / Debian
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# 重新登录 SSH 使组生效
```

## 2. 克隆代码

```bash
git clone https://github.com/<your-username>/EchoIM.git
cd EchoIM
```

## 3. 配置环境变量

```bash
cp .env.example .env
```

编辑 `.env`，**务必修改以下值**：

| 变量 | 说明 |
|------|------|
| `POSTGRES_PASSWORD` | 数据库密码，使用 `openssl rand -hex 32` 生成 |
| `JWT_SECRET` | JWT 签名密钥，使用 `openssl rand -hex 32` 生成 |
| `INVITE_CODES` | 注册邀请码，多个用逗号分隔（如 `code1,code2`）。未设置时所有注册将被拒绝 |

其余变量可保持默认值。

## 4. 构建并启动

```bash
docker compose --profile deploy up -d --build
```

首次启动时，服务端会自动运行数据库迁移。

查看日志确认服务正常：

```bash
docker compose logs -f
```

## 5. 验证

浏览器访问 `http://<VM公网IP>`，应看到 EchoIM 登录页面。

## 6. 端到端冒烟测试（12.7）

1. 注册用户 A 和用户 B
2. 用户 A 搜索用户 B 并发送好友请求
3. 用户 B 接受好友请求
4. 用户 A 向用户 B 发送消息
5. 确认用户 B 实时收到消息
6. 确认输入提示和在线状态正常

## 常用运维命令

```bash
# 查看服务状态
docker compose --profile deploy ps

# 查看日志
docker compose --profile deploy logs -f server

# 重启服务
docker compose --profile deploy restart server

# 停止所有服务
docker compose --profile deploy down

# 停止并清除数据
docker compose --profile deploy down -v
```

## 更新部署

```bash
git pull
docker compose --profile deploy up -d --build
```

## 附录：多实例验证（可选）

`docker-compose.yml` 中还提供了一个独立的 `multi` profile，用于本地验证 Redis Pub/Sub 跨实例消息投递和在线状态广播（Redis 适配阶段 7 引入）。它**不是生产部署路径**——没有 TLS、没有健康检查、nginx 配置也未做生产级调优，只用来复现多副本场景下的 WS 行为。

```bash
# 启动两个 server 副本 + nginx 负载均衡（复用同一个 postgres/redis）
docker compose --profile multi up -d --build

# 查看两个实例日志（另开终端）
docker compose --profile multi logs -f server-1
docker compose --profile multi logs -f server-2

# 停止
docker compose --profile multi down
```

拓扑：nginx 监听 `${SERVER_PORT:-3000}`，轮询到 `server-1:3000` / `server-2:3000`；消息通过 Redis Pub/Sub 跨实例投递，所以无需会话粘性。

验证项见 `redis-adapter-plan.md` §7.2（跨实例收消息 / presence / typing / 优雅重启 / 强制 kill 后 60~90s offline）。

> 注意：`multi` 和 `deploy` 两个 profile **不要同时启动**——它们都会尝试占用 `${SERVER_PORT:-3000}` 端口。
