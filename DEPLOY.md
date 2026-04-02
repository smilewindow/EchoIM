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
