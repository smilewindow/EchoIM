# Redis 适配层实现计划

## 背景与目标

当前 EchoIM 的 WebSocket 广播和在线状态全部依赖单进程内存 `Map<userId, Set<WebSocket>>`。这意味着：
- 只能跑单个 server 实例
- 重启后在线状态全部丢失
- 面试中被问"如何水平扩展"时只能纸上谈兵

**目标：** 引入 Redis 作为跨实例的消息总线和在线状态存储，使多个 server 实例可以协同工作。

## 架构变化

```
当前:
  Client ──WS──▶ Server (内存 Map) ──▶ 本地 WebSocket

目标:
  Client ──WS──▶ Server-1 ──publish──▶ Redis Pub/Sub ──▶ Server-2 ──▶ 本地 WebSocket
                     │                      │
                     └── ZADD/ZSCORE ──▶ Redis (在线状态 Sorted Set) ◀──┘
```

## 需要改动的文件

| 文件 | 改动 |
|------|------|
| `docker-compose.yml` | 新增 `redis` 服务 |
| `server/package.json` | 新增 `ioredis` 依赖 |
| `server/src/plugins/redis.ts` | **新建** — Redis 连接插件 + Lua 脚本注册 |
| `server/src/plugins/ws.ts` | 重构 broadcast → Redis Pub/Sub；在线状态 → Redis Sorted Set + Lua 原子操作 |
| `server/src/index.ts` | 新增 `REDIS_URL` 环境变量检查 |
| `server/src/app.ts` | 注册 redis 插件 |
| `.env.example` | 新增 `REDIS_URL` |
| 测试文件 | 适配 Redis，新增跨实例测试 |

---

## 阶段 1 — 基础设施（Redis 服务 + 连接）

### 1.1 docker-compose.yml 新增 Redis 服务

```yaml
redis:
  image: redis:7-alpine
  restart: unless-stopped
  ports:
    - "${REDIS_PORT:-6379}:6379"
  volumes:
    - redis-data:/data
```

同时在 `server` 服务的 `environment` 中新增：
```yaml
REDIS_URL: redis://redis:6379
```

### 1.2 安装 ioredis 依赖

```bash
npm install ioredis --prefix server
npm install @types/ioredis -D --prefix server
```

### 1.3 新建 server/src/plugins/redis.ts

Fastify 插件，职责：
- 创建两个 Redis 客户端：`pub`（发布/通用命令）和 `sub`（订阅专用）
- ioredis 要求订阅客户端与发布客户端分开，因为进入订阅模式后该客户端不能执行其他命令
- 通过 `fastify.redis` 暴露 `{ pub, sub }`
- 注册 Lua 脚本（`defineCommand`），供阶段 2 的原子 presence 操作使用
- `onClose` 钩子中 `disconnect()` 两个客户端

类型声明：
```ts
declare module 'fastify' {
  interface FastifyInstance {
    redis: { pub: Redis; sub: Redis }
  }
}
```

### 1.4 更新 server/src/index.ts 和 .env.example

- `index.ts` 新增 `REDIS_URL` 环境变量检查（非强制，提供默认值 `redis://localhost:6379`）
- `app.ts` 中在 `dbPlugin` 之后、`wsPlugin` 之前注册 `redisPlugin`（因为 ws 插件依赖 redis）
- `.env.example` 新增 `REDIS_URL=redis://localhost:6379`

---

## 阶段 2 — 在线状态迁移到 Redis（Sorted Set 租约模型）

### 2.1 数据模型：Sorted Set + per-member 过期

**不使用 Set + key 级 TTL**（会导致僵尸连接被续命），改用 Sorted Set：

```
presence:{userId} → SortedSet { member: "instanceId:socketId", score: expireTimestamp }
```

- `score` = 该 member 的过期时间戳（由 Lua 脚本在 Redis 端通过 `TIME` 计算：`redisNow + 60_000`）
- 心跳只续期**本实例**的 member（更新 score），不影响其他实例的 member
- 清扫时通过 `ZREMRANGEBYSCORE presence:{userId} -inf {now}` 移除过期 member

这样当 server-1 崩溃时，server-2 的心跳只续自己的 member，server-1 留下的僵尸 member 会在 60s 后被清扫。

### 2.2 Lua 原子脚本：连接上线

**为什么需要原子操作：** 如果用 `ZCARD` → `ZADD` 分两步，两个实例同时为同一用户建连时，都可能看到 `ZCARD=0`，各发一次 `presence.online`。

```lua
-- presence_connect.lua
-- KEYS[1] = presence:{userId}
-- ARGV[1] = "instanceId:socketId"
-- ARGV[2] = leaseDurationMs (60000)
-- 返回: 1 = 该用户从 0→1（需广播 online），0 = 已有其他连接
-- 注意：时间基准统一使用 Redis TIME，不依赖客户端时钟

-- 获取 Redis 服务器时间（秒 + 微秒 → 毫秒）
local t = redis.call('TIME')
local now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
local expireAt = now + tonumber(ARGV[2])

-- 先清理过期 member
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', now)
-- 清理后统计存活连接数
local before = redis.call('ZCARD', KEYS[1])
-- 添加新连接
redis.call('ZADD', KEYS[1], expireAt, ARGV[1])
-- 0→1 转换
if before == 0 then
  return 1
end
return 0
```

### 2.3 Lua 原子脚本：连接下线

```lua
-- presence_disconnect.lua
-- KEYS[1] = presence:{userId}
-- ARGV[1] = "instanceId:socketId"
-- 返回: 1 = 移除自己后该用户无任何活连接（需广播 offline），0 = 仍有活连接或无变化
--
-- 设计原则：disconnect 只管"移除自己 + 判断是否还有活 member"。
-- 批量清理过期 member（ZREMRANGEBYSCORE）统一由 sweep 负责。
-- 当 disconnect 发现无活连接时，直接 DEL 整个 key（残留的只可能是过期僵尸），
-- 这样 sweep 不会再看到该 key，避免重复广播 presence.offline。

local t = redis.call('TIME')
local now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)

-- 检查自己是否还在（可能已被 sweep 清理）
local selfScore = redis.call('ZSCORE', KEYS[1], ARGV[1])
if not selfScore then
  -- 自己已经不在了，不产生边沿
  return 0
end

-- 移除自己
redis.call('ZREM', KEYS[1], ARGV[1])

-- 检查是否还有未过期的活连接（不删除过期 member，只计数）
local alive = redis.call('ZCOUNT', KEYS[1], '(' .. now, '+inf')
if alive == 0 then
  -- 没有活连接了。剩余的只可能是过期 member（僵尸），直接 DEL 整个 key。
  -- 这样 sweep 不会再看到这个 key，避免重复广播 presence.offline。
  redis.call('DEL', KEYS[1])
  return 1
end
return 0
```

### 2.4 修改 ws.ts — 连接时

```ts
// 本地仍保留 wsConnections（用于本地投递）
if (!wsConnections.has(userId)) wsConnections.set(userId, new Set())
sockets.add(ws)

// 原子操作：清理过期 + 添加 + 判断 0→1（时间基准由 Redis TIME 提供）
const becameOnline = await redis.pub.presenceConnect(
  `presence:${userId}`,
  `${instanceId}:${socketId}`,
  60_000  // leaseDurationMs
)
if (becameOnline === 1) {
  broadcastPresence(userId, 'presence.online')
}
```

### 2.5 修改 ws.ts — 断开时

```ts
sockets.delete(ws)
if (sockets.size === 0) wsConnections.delete(userId)

// 原子操作：移除自己 + 判断是否还有活连接（不清理过期 member，由 sweep 负责）
const becameOffline = await redis.pub.presenceDisconnect(
  `presence:${userId}`,
  `${instanceId}:${socketId}`
)
if (becameOffline === 1 && !closing) {
  broadcastPresence(userId, 'presence.offline')
}
```

### 2.6 心跳续期（per-member）

每 30 秒只更新**本实例拥有的** member 的 score。

为保持时间基准统一，续期也通过 Lua 脚本在 Redis 端计算过期时间：

```lua
-- presence_heartbeat.lua
-- KEYS[1] = presence:{userId}
-- ARGV[1] = "instanceId:socketId"
-- ARGV[2] = leaseDurationMs (60000)
local t = redis.call('TIME')
local now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
local expireAt = now + tonumber(ARGV[2])
-- 只在 member 存在时更新（XX），防止给已清理的僵尸续命
redis.call('ZADD', KEYS[1], 'XX', expireAt, ARGV[1])
return 0
```

```ts
const heartbeatTimer = setInterval(async () => {
  const pipeline = redis.pub.pipeline()
  for (const [userId, sockets] of wsConnections.entries()) {
    for (const ws of sockets) {
      const socketId = wsSocketIds.get(ws)
      if (socketId) {
        pipeline.presenceHeartbeat(
          `presence:${userId}`,
          `${instanceId}:${socketId}`,
          60_000
        )
      }
    }
  }
  await pipeline.exec()
}, 30_000)
```

### 2.7 在线状态查询改造

`sendPresenceSnapshot` 和 `broadcastPresence` 中判断好友是否在线。

为保持时间基准统一，在线状态查询也通过 Lua 脚本完成：

```lua
-- presence_check.lua（非破坏性查询，不删除数据）
-- KEYS[1] = presence:{userId}
-- 返回: 1 = 在线（存在至少一个未过期 member），0 = 离线
-- 重要：此脚本只读不写，"删过期 member + 产生 offline 边沿"
-- 的职责统一收口在 sweep 路径中，避免查询路径提前"吃掉"边沿。
local t = redis.call('TIME')
local now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
-- 查询 score > now 的 member 数量（即未过期的连接）
local alive = redis.call('ZCOUNT', KEYS[1], '(' .. now, '+inf')
return alive > 0 and 1 or 0
```

```ts
async function isUserOnline(userId: number): Promise<boolean> {
  return (await redis.pub.presenceCheck(`presence:${userId}`)) === 1
}
```

> 优化：批量查询时可用 pipeline 调用多次 `presenceCheck`，减少网络往返。
> 设计原则：**过期 member 的批量清理（ZREMRANGEBYSCORE）只在 sweep 中执行**。disconnect 只移除自己（ZREM）并在无活连接时 DEL 整个 key。查询路径（presenceCheck）只做 ZCOUNT 判断，不删数据。这确保每个 offline 边沿只由一个路径产生，不会重复广播。

### 2.8 僵尸连接清扫 + 补发 offline 事件

**问题：** Redis key 过期是静默的，不会自动给好友推 `presence.offline`。客户端是纯事件驱动的，如果没人补发 offline，用户界面会一直显示"在线"。

**方案：** 每个实例定期运行清扫任务，用 Redis 分布式锁保证只有一个实例执行：

清扫也通过 Lua 脚本在 Redis 端使用 `TIME`，避免时钟漂移：

```lua
-- presence_sweep_key.lua
-- KEYS[1] = presence:{userId}
-- 返回: 1 = 该用户从有连接变为无连接（需补发 offline），0 = 无变化
local t = redis.call('TIME')
local now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
local before = redis.call('ZCARD', KEYS[1])
if before == 0 then return 0 end
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', now)
local after = redis.call('ZCARD', KEYS[1])
if after == 0 and before > 0 then
  redis.call('DEL', KEYS[1])
  return 1
end
return 0
```

```ts
const SWEEP_INTERVAL = 30_000  // 30 秒
const SWEEP_LOCK_KEY = 'presence:sweep:lock'
const SWEEP_LOCK_TTL = 10_000  // 10 秒

const sweepTimer = setInterval(async () => {
  // 争抢分布式锁，只有一个实例执行清扫
  const acquired = await redis.pub.set(SWEEP_LOCK_KEY, instanceId, 'PX', SWEEP_LOCK_TTL, 'NX')
  if (!acquired) return

  try {
    // 扫描所有 presence:* key（排除锁 key）
    let cursor = '0'
    do {
      const [nextCursor, keys] = await redis.pub.scan(cursor, 'MATCH', 'presence:*', 'COUNT', 100)
      cursor = nextCursor

      for (const key of keys) {
        if (key === SWEEP_LOCK_KEY) continue
        // 原子清扫：清理过期 member，判断是否从 >0→0
        const becameOffline = await redis.pub.presenceSweepKey(key)
        if (becameOffline === 1) {
          const userId = parseInt(key.split(':')[1])
          await broadcastPresence(userId, 'presence.offline')
        }
      }
    } while (cursor !== '0')
  } catch (err) {
    fastify.log.error(err, 'presence sweep error')
  }
}, SWEEP_INTERVAL)
```

在 `onClose` 钩子中 `clearInterval(sweepTimer)`。

---

## 阶段 3 — 消息广播迁移到 Redis Pub/Sub

### 3.1 频道设计

使用 per-user 频道：
```
channel: user:{userId}
```

每个 server 实例订阅当前连接到它的所有用户的频道。当用户连接到本实例时订阅，最后一个连接断开时取消订阅。

### 3.2 每用户订阅状态机 + Subscribe-before-ready

**问题 A：** 如果 socket 已经接入但 `SUBSCRIBE` 还没完成，此时 `PUBLISH` 的消息会丢失。
**问题 B：** 仅靠 `sockets.size` 判断是否 subscribe/unsubscribe，并发的同用户连接/断开会导致订阅状态与实际不一致（如：一个早退连接在另一个还在 subscribing 时先 unsubscribe）。

**方案：** 引入 per-user 订阅状态机，用 `pendingInits` 计数器追踪正在初始化的连接数，串行化同用户的 subscribe/unsubscribe 决策：

```ts
// 每用户订阅状态：管理 subscribe/unsubscribe 生命周期
interface UserSubState {
  status: 'subscribing' | 'subscribed' | 'unsubscribing' | 'unsubscribed'
  readySockets: Set<WebSocket>   // 已完成初始化的连接
  pendingInits: number           // 正在初始化中的连接数（还没加入 readySockets）
  // 串行化 subscribe/unsubscribe 操作，防止并发冲突
  queue: Promise<void>
}

const userSubStates = new Map<number, UserSubState>()

function getOrCreateSubState(userId: number): UserSubState {
  if (!userSubStates.has(userId)) {
    userSubStates.set(userId, {
      status: 'unsubscribed',
      readySockets: new Set(),
      pendingInits: 0,
      queue: Promise.resolve(),
    })
  }
  return userSubStates.get(userId)!
}

// 串行化同用户的订阅操作，返回一个 Promise
function enqueueSubOp(state: UserSubState, op: () => Promise<void>): Promise<void> {
  state.queue = state.queue.then(op, op)
  return state.queue
}

// 统一的 unsubscribe + 回收逻辑，避免重复代码
async function tryUnsubscribeAndReclaim(userId: number, state: UserSubState) {
  // 如果还有活跃或正在初始化的连接，什么都不做
  if (state.readySockets.size > 0 || state.pendingInits > 0) return

  // 步骤 1：如果需要，执行 unsubscribe
  if (state.status === 'subscribed' || state.status === 'subscribing') {
    state.status = 'unsubscribing'
    try {
      await redis.sub.unsubscribe(`user:${userId}`)
    } catch (err) {
      // unsubscribe 失败时记录日志，但仍标记为 unsubscribed
      // 因为此时已经没有 ready/pending 连接，保持 subscribing/subscribed 反而会
      // 让后续连接跳过真正的 subscribe 调用
      fastify.log.error(err, `failed to unsubscribe user:${userId}`)
    }
    state.status = 'unsubscribed'
  }

  // 步骤 2：回收空闲 state（独立于步骤 1，即使 status 已经是 unsubscribed 也能进入）
  // 场景：subscribe 失败后 status 已回滚为 unsubscribed，close 路径进来时
  // 步骤 1 会被跳过，但步骤 2 仍然可以回收这个空 state
  // 二次检查：unsubscribe 是异步的，等待期间可能有新连接进来
  if (
    userSubStates.get(userId) === state &&
    state.readySockets.size === 0 &&
    state.pendingInits === 0 &&
    state.status === 'unsubscribed'
  ) {
    userSubStates.delete(userId)
  }
}
```

**连接初始化流程：**

```ts
wss.on('connection', async (ws, request) => {
  const userId = userIdMap.get(request)!
  const socketId = crypto.randomUUID()
  let initialized = false
  const state = getOrCreateSubState(userId)

  // 立即递增 pendingInits（在任何 await 之前）
  state.pendingInits++

  // 立即挂上 close 清理
  // pendingInits 的所有权统一在 close 回调中管理（未初始化时），
  // 避免 catch + close 双重递减导致负数。
  ws.on('close', async () => {
    wsSocketIds.delete(ws)
    if (!initialized) {
      // 还没完成初始化就断开了 —— 只在这里递减 pendingInits
      state.pendingInits--
      // 通过队列串行化：只有当 ready + pending 都为 0 时才 unsubscribe
      await enqueueSubOp(state, async () => {
        await tryUnsubscribeAndReclaim(userId, state)
      })
      return
    }
    // === 正常断开清理 ===
    state.readySockets.delete(ws)
    // 同步更新 wsConnections
    const localSockets = wsConnections.get(userId)
    if (localSockets) {
      localSockets.delete(ws)
      if (localSockets.size === 0) wsConnections.delete(userId)
    }
    // 通过队列串行化 unsubscribe 决策
    await enqueueSubOp(state, async () => {
      await tryUnsubscribeAndReclaim(userId, state)
    })
    // presence 下线
    const becameOffline = await redis.pub.presenceDisconnect(
      `presence:${userId}`,
      `${instanceId}:${socketId}`
    )
    if (becameOffline === 1 && !closing) {
      broadcastPresence(userId, 'presence.offline')
    }
  })

  try {
    wsSocketIds.set(ws, socketId)

    // 通过队列串行化：需要 subscribe 时等待完成
    // subscribe 失败时用 try/catch 回滚状态，防止卡在 subscribing
    await enqueueSubOp(state, async () => {
      if (state.status === 'unsubscribed' || state.status === 'unsubscribing') {
        state.status = 'subscribing'
        try {
          await redis.sub.subscribe(`user:${userId}`)
          state.status = 'subscribed'
        } catch (err) {
          // 订阅失败，回滚状态，让后续连接可以重试
          state.status = 'unsubscribed'
          throw err  // 继续向外层抛出
        }
      }
      // 如果已经是 subscribed，直接通过
      // 如果是 subscribing，等队列前面的操作完成即可
    })

    // 检查客户端是否在 await 期间断开
    if (ws.readyState !== WebSocket.OPEN) return

    // 订阅已就绪，从 pending 转为 ready
    state.pendingInits--
    state.readySockets.add(ws)

    // 同时更新 wsConnections（供本地投递使用）
    if (!wsConnections.has(userId)) wsConnections.set(userId, new Set())
    wsConnections.get(userId)!.add(ws)

    // ★ 立即标记 initialized，确保此后 close 走"正常断开"分支
    // 此时 ws 已在 readySockets + wsConnections 中，close 回调需要从中移除
    initialized = true

    // 原子操作注册 presence（时间基准由 Redis TIME 提供）
    // 如果这里或后续步骤失败，catch 调用 ws.close()，
    // close 回调走 initialized=true 分支，正确清理 readySockets/wsConnections/presence
    const becameOnline = await redis.pub.presenceConnect(
      `presence:${userId}`,
      `${instanceId}:${socketId}`,
      60_000
    )
    if (becameOnline === 1) {
      broadcastPresence(userId, 'presence.online')
        .catch((e) => fastify.log.error(e, 'broadcastPresence failed'))
    }

    // snapshot 失败不应中断连接，catch 后记日志即可
    await sendPresenceSnapshot(userId, ws)
      .catch((e) => fastify.log.error(e, 'sendPresenceSnapshot failed'))

    // 注册 message 事件处理器（typing 等）...
  } catch (err) {
    // initialized=false 时：pendingInits 由 close 回调递减
    // initialized=true 时：close 回调走正常分支，从 readySockets/wsConnections 中移除，
    //   并执行 presenceDisconnect 清理 Redis（即使 presenceConnect 没跑过，
    //   disconnect 的 Lua 脚本对不存在的 member 执行 ZREM 也只会返回 0，安全无副作用）
    fastify.log.error(err, 'ws connection init failed')
    ws.close()
  }
})
```

> **关键保障：**
> - `enqueueSubOp` 把同一用户的所有 subscribe/unsubscribe 操作串入一个 Promise 链，消除并发竞态。
> - `pendingInits` 的递减**统一由 close 回调负责**（未初始化时），catch 只调用 `ws.close()` 触发 close 事件，避免双重递减导致负数。
> - subscribe 失败时通过 try/catch 将状态回滚到 `unsubscribed`，后续连接可以重试，不会卡在 `subscribing`。
> - 过期 member 的批量清理（`ZREMRANGEBYSCORE`）只在 sweep 中执行。disconnect 只移除自己（`ZREM`）并在无活连接时 `DEL` 整个 key。查询路径（`presenceCheck`）只做 `ZCOUNT` 判断不删数据。每个 offline 边沿只由一个路径产生，不会重复广播。

### 3.3 重构 broadcast 函数

原逻辑（直接本地投递）：
```ts
function broadcast(userId, event) {
  const sockets = wsConnections.get(userId)
  if (!sockets) return
  const msg = JSON.stringify(event)
  for (const socket of sockets) {
    if (socket.readyState === WebSocket.OPEN) socket.send(msg)
  }
}
```

新逻辑（发布到 Redis）：
```ts
function broadcast(userId, event) {
  // 发布到 Redis，所有订阅了该频道的实例都会收到
  // publish 返回 Promise，必须 catch 避免未处理的拒绝
  redis.pub.publish(`user:${userId}`, JSON.stringify(event))
    .catch((err) => fastify.log.error(err, 'redis publish failed'))
}
```

### 3.4 订阅消息的本地投递

每个实例监听 Redis 消息，投递给本地持有的 WebSocket：
```ts
redis.sub.on('message', (channel, message) => {
  // channel = "user:123"
  const userId = parseInt(channel.split(':')[1])
  const sockets = wsConnections.get(userId)
  if (!sockets) return
  for (const socket of sockets) {
    if (socket.readyState === WebSocket.OPEN) socket.send(message)
  }
})
```

### 3.5 动态取消订阅

取消订阅的逻辑已经集成在 3.2 的订阅状态机中：当 `readySockets.size === 0 && pendingInits === 0` 时，通过 `enqueueSubOp` 串行执行 `unsubscribe`。同时更新 `wsConnections`（从 `readySockets` 中 delete 后同步删除）。

---

## 阶段 4 — 在线状态广播适配

### 4.1 修改 broadcastPresence

`broadcastPresence` 中原有的 race condition 防护需要适配为查询 Redis：

```ts
async function broadcastPresence(userId: number, type: 'presence.online' | 'presence.offline') {
  const result = await fastify.pool.query(/* 查好友列表 */)

  // 异步 DB 查询后 re-check — 改为查 Redis
  const nowOnline = await isUserOnline(userId)
  if (type === 'presence.online' && !nowOnline) return
  if (type === 'presence.offline' && nowOnline) return

  for (const row of result.rows) {
    const friendId = row.friend_id as number
    // broadcast 已走 Redis Pub/Sub，无需再判断 friendId 是否在本地
    fastify.broadcast(friendId, { type, payload: { user_id: userId } })
  }
}
```

### 4.2 修改 sendPresenceSnapshot

```ts
async function sendPresenceSnapshot(userId: number, ws: WebSocket) {
  const result = await fastify.pool.query(/* 查好友列表 */)
  const friendIds = result.rows.map(r => r.friend_id as number)

  // 批量查询好友在线状态（pipeline + Lua 脚本，时间基准统一由 Redis TIME 提供）
  const pipeline = redis.pub.pipeline()
  for (const fid of friendIds) {
    pipeline.presenceCheck(`presence:${fid}`)
  }
  const results = await pipeline.exec()

  for (let i = 0; i < friendIds.length; i++) {
    const isOnline = results![i]![1] === 1
    if (isOnline && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'presence.online', payload: { user_id: friendIds[i] } }))
    }
  }
}
```

---

## 阶段 5 — 优雅下线与崩溃恢复

### 5.1 优雅下线（Graceful Shutdown）

当前代码在关闭时设置 `closing = true` 并跳过 offline 广播。单实例时问题不大，但多实例 rolling restart 时，用户会"假在线"整个 TTL 窗口。

新的关闭流程：

```ts
fastify.addHook('onClose', async () => {
  closing = true

  // 1. 停止心跳和清扫定时器
  clearInterval(heartbeatTimer)
  clearInterval(sweepTimer)

  // 2. 主动清理本实例所有 presence member，并补发 offline
  for (const [userId, sockets] of wsConnections.entries()) {
    for (const ws of sockets) {
      const socketId = wsSocketIds.get(ws)
      if (socketId) {
        const becameOffline = await redis.pub.presenceDisconnect(
          `presence:${userId}`,
          `${instanceId}:${socketId}`
        )
        if (becameOffline === 1) {
          // 直接通过 Redis Pub/Sub 广播 offline（其他实例会投递）
          await broadcastPresence(userId, 'presence.offline')
        }
      }
    }
  }

  // 3. 关闭所有 WebSocket 连接
  for (const client of wss.clients) {
    client.terminate()
  }
  await new Promise<void>((resolve) => wss.close(() => resolve()))

  // 4. Redis 连接由 redis 插件的 onClose 钩子关闭
})
```

### 5.2 崩溃恢复

实例崩溃（进程被 kill -9、OOM 等）时无法执行优雅下线。此时依赖：

1. **per-member 过期：** 崩溃实例的 member score 不再被续期，60s 后过期
2. **清扫任务：** 其他存活实例的清扫任务（每 30s）会发现过期 member，清理后补发 `presence.offline`
3. **最坏延迟：** lease 60s + sweep 间隔最多 30s = **60~90s**。测试断言和文档 SLA 均以此为准
3. **最坏情况：** 所有实例同时崩溃 → 重启后第一次清扫会清理所有僵尸，但此时没有在线用户需要接收 offline 事件 → 下次用户连接时会拿到正确的 snapshot

---

## 阶段 6 — 测试适配

### 6.1 测试策略：真实 Redis

与 PostgreSQL 测试策略保持一致，测试环境使用真实 Redis：
- Docker Compose 已有 Redis 服务，测试直接连
- 使用 Redis DB 1 隔离测试数据，避免误清开发库

### 6.2 更新 server/tests/env-setup.ts

**关键：** 必须在 env-setup.ts 中显式注入测试用 REDIS_URL，否则 `flushRedis()` 会打到开发库的默认 DB 0。

当前 env-setup.ts 只改了 `DATABASE_URL`，需新增：
```ts
// 测试 Redis 使用 DB 1，与开发环境的 DB 0 隔离
process.env['REDIS_URL'] = process.env['TEST_REDIS_URL'] ?? 'redis://localhost:6379/1'
```

完整的 env-setup.ts 改动：
```ts
dotenv.config({ path: ... })

const base = process.env['DATABASE_URL']
if (!base) throw new Error('DATABASE_URL must be set in .env before running tests')

process.env['DATABASE_URL'] = base.replace(/\/[^/]+$/, '/echoim_test')
process.env['JWT_SECRET'] = process.env['JWT_SECRET'] ?? 'test-secret-for-vitest'
// ↓ 新增：测试 Redis 使用 DB 1，避免 FLUSHDB 清掉开发数据
process.env['REDIS_URL'] = process.env['TEST_REDIS_URL'] ?? 'redis://localhost:6379/1'
```

### 6.3 更新测试辅助函数

`server/tests/helpers/` 中：
- `buildApp()` 需确保 redis 插件正常初始化（它会读取 `process.env['REDIS_URL']`，此时已被 env-setup.ts 指向 DB 1）
- 新增 `flushRedis()` 辅助函数，调用 `FLUSHDB`（只清 DB 1）

### 6.4 测试生命周期

每个测试用例：
```ts
beforeEach(async () => {
  await truncateAll()   // 清理 PG
  await flushRedis()    // 清理 Redis DB 1（FLUSHDB）
})
```

跨实例测试每个 case 独立创建/关闭 app 实例，避免订阅和心跳跨测试泄漏：
```ts
afterEach(async () => {
  await app1?.close()
  await app2?.close()
})
```

### 6.5 现有 WS 测试适配

现有 WS 测试（认证、广播、在线状态等）逻辑不变，只需确保：
- 测试环境 Redis 可连接（env-setup.ts 已配好）
- 生命周期中正确清理 Redis

### 6.6 新增集成测试：跨实例场景

```ts
describe('cross-instance broadcast', () => {
  let app1, app2

  beforeEach(async () => {
    await flushRedis()
    app1 = await buildApp()  // 实例 1
    app2 = await buildApp()  // 实例 2（共享同一 Redis + PG）
  })

  afterEach(async () => {
    await app1.close()
    await app2.close()
  })

  it('跨实例消息投递', async () => {
    // 用户 A 通过 app1 的 WS 连接
    // 用户 B 通过 app2 的 WS 连接
    // A 通过 app1 发送消息
    // 验证 B 在 app2 上收到 message.new 事件
  })

  it('跨实例在线状态可见', async () => {
    // 用户 A 连实例 1，用户 B 连实例 2
    // B 应收到 A 的 presence.online
    // A 断开后 B 应收到 presence.offline
  })
})

describe('crash recovery', () => {
  it('实例崩溃后僵尸 member 被清扫并补发 offline', async () => {
    // app1 必须用子进程启动（同进程 buildApp 的 close 钩子会正常执行，无法模拟真正崩溃）
    // 使用 tsx 直接运行 TS 源码，避免依赖 build 产物
    const app1Process = fork('src/index.ts', {
      execArgv: ['--import', 'tsx'],
      env: { ...testEnv, PORT: '3001' },
    })
    const app2 = await buildApp()  // app2 在测试进程内，用于接收事件

    // 用户 A 通过 app1（子进程，端口 3001）建立 WS 连接
    // 用户 B 通过 app2 建立 WS 连接
    // B 收到 A 的 presence.online

    // 模拟崩溃：SIGKILL 子进程（不触发任何 close/exit 钩子）
    process.kill(app1Process.pid!, 'SIGKILL')

    // 等待 lease 过期 + sweep 周期（测试中可缩短为秒级以加速）
    // B 应收到 A 的 presence.offline
  })
})

describe('subscribe failure / early disconnect cleanup', () => {
  it('subscribe 失败后 userSubStates 被回收', async () => {
    const app = await buildApp()
    // mock redis.sub.subscribe 使其抛错
    // 建立 WS 连接 → 初始化失败 → ws.close() 触发 close 回调
    // 验证 userSubStates 中该 userId 的 state 已被 delete
  })

  it('初始化期间客户端提前断开后 userSubStates 被回收', async () => {
    const app = await buildApp()
    // 建立 WS 连接，在 subscribe 完成前主动断开
    // 验证 userSubStates 中该 userId 的 state 已被 delete
    // 验证 pendingInits 没有变成负数
  })
})

describe('graceful shutdown', () => {
  it('实例优雅关闭时主动补发 offline', async () => {
    const app1 = await buildApp()
    const app2 = await buildApp()
    // 用户 A 连实例 1，用户 B 连实例 2
    // 正常关闭 app1
    // B 应立即收到 A 的 presence.offline（不需要等 TTL）
  })
})
```

---

## 阶段 7 — Docker Compose 多实例验证

### 7.1 更新 docker-compose.yml

新增 nginx 负载均衡（支持 WebSocket upgrade）+ server 多副本：

```yaml
nginx:
  image: nginx:alpine
  profiles: [deploy]
  depends_on:
    - server-1
    - server-2
  ports:
    - "${SERVER_PORT:-3000}:3000"
  volumes:
    - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro

server-1:
  build: ./server
  profiles: [deploy]
  environment:
    # ... 同原 server，加上 REDIS_URL

server-2:
  build: ./server
  profiles: [deploy]
  environment:
    # ... 同 server-1
```

nginx.conf 需配置 WebSocket upgrade 支持：
```nginx
upstream backend {
  server server-1:3000;
  server server-2:3000;
}

server {
  listen 3000;
  location / {
    proxy_pass http://backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
```

### 7.2 手工验证清单

- [ ] 用户 A 连到 server-1，用户 B 连到 server-2
- [ ] A 给 B 发消息，B 实时收到
- [ ] 在线状态跨实例正确显示
- [ ] 一个实例优雅重启后，另一个实例上的用户立即收到 offline/online
- [ ] 一个实例强制 kill 后，另一个实例上的用户在 60~90s 内收到 offline（lease 60s + sweep 间隔最多 30s）
- [ ] 输入提示跨实例正常工作

---

## 实施顺序与依赖

```
阶段 1（基础设施）
  └─ 阶段 2（在线状态 — Sorted Set + Lua 原子脚本 + 清扫）
       └─ 阶段 3（消息广播 — Pub/Sub + Subscribe-before-ready）
            └─ 阶段 4（在线状态广播适配 — pipeline 批量查询）
                 └─ 阶段 5（优雅下线与崩溃恢复）
                      └─ 阶段 6（测试适配）
                           └─ 阶段 7（多实例验证）
```

阶段 1→2→3→4→5 必须顺序执行。阶段 6 可与 4/5 交叉进行。

## 客户端影响

**无。** 客户端代码零改动。Redis 适配层完全是服务端内部重构，对外暴露的 REST API 和 WebSocket 协议不变。
