import fp from 'fastify-plugin'
import { WebSocketServer, WebSocket } from 'ws'
import crypto from 'node:crypto'
import type { IncomingMessage } from 'http'
import type { FastifyInstance } from 'fastify'
import jwt from 'jsonwebtoken'

declare module 'fastify' {
  interface FastifyInstance {
    broadcast: (userId: number, event: { type: string; payload: unknown }) => void
    wsConnections: Map<number, Set<WebSocket>>
  }
}

const instanceId = crypto.randomUUID()
const presenceKey = (userId: number) => `presence:${userId}`
const memberKey = (socketId: string) => `${instanceId}:${socketId}`

export default fp(async function wsPlugin(fastify: FastifyInstance) {
  const wsConnections = new Map<number, Set<WebSocket>>()
  const userIdMap = new WeakMap<IncomingMessage, number>()
  const wsSocketIds = new Map<WebSocket, string>()
  const pendingPresenceCloseTasks = new Set<Promise<void>>()
  const wss = new WebSocketServer({ noServer: true })
  const LEASE_MS = 60_000

  fastify.decorate('wsConnections', wsConnections)
  fastify.decorate('broadcast', function (userId: number, event: { type: string; payload: unknown }) {
    const sockets = wsConnections.get(userId)
    if (!sockets) return
    const msg = JSON.stringify(event)
    for (const socket of sockets) {
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(msg)
      }
    }
  })

  async function getFriendIds(userId: number): Promise<number[]> {
    const result = await fastify.pool.query(
      `SELECT CASE WHEN sender_id = $1 THEN recipient_id ELSE sender_id END AS friend_id
       FROM friend_requests
       WHERE status = 'accepted' AND (sender_id = $1 OR recipient_id = $1)`,
      [userId]
    )
    return result.rows.map((r: { friend_id: number }) => r.friend_id)
  }

  async function checkFriendsOnline(friendIds: number[]): Promise<Map<number, boolean>> {
    if (friendIds.length === 0) return new Map()
    const pipeline = fastify.redis.pub.pipeline()
    for (const id of friendIds) {
      pipeline.presenceCheck(presenceKey(id))
    }
    const results = await pipeline.exec()
    const onlineMap = new Map<number, boolean>()
    for (let i = 0; i < friendIds.length; i++) {
      // pipeline.exec() returns [err, result][] — err is null on success
      onlineMap.set(friendIds[i], results?.[i]?.[1] === 1)
    }
    return onlineMap
  }

  function registerPresence(userId: number, socketId: string): void {
    fastify.redis.pub.presenceConnect(
      presenceKey(userId), memberKey(socketId), LEASE_MS
    ).then((becameOnline) => {
      if (becameOnline === 1) {
        return broadcastPresence(userId, 'presence.online')
      }
    }).catch((err: unknown) => fastify.log.error(err))
  }

  async function broadcastPresence(userId: number, type: 'presence.online' | 'presence.offline') {
    try {
      const friendIds = await getFriendIds(userId)
      // Re-check state after the async DB round-trip via Redis (cross-instance aware)
      const nowOnline = (await fastify.redis.pub.presenceCheck(presenceKey(userId))) === 1
      if (type === 'presence.online' && !nowOnline) return
      if (type === 'presence.offline' && nowOnline) return

      const onlineMap = await checkFriendsOnline(friendIds)
      for (const friendId of friendIds) {
        if (onlineMap.get(friendId)) {
          fastify.broadcast(friendId, { type, payload: { user_id: userId } })
        }
      }
    } catch (err) {
      fastify.log.error(err)
    }
  }

  // Send the newcomer a snapshot of which friends are already online so clients
  // don't have to wait for a disconnect/reconnect cycle to learn current state.
  async function sendPresenceSnapshot(userId: number, ws: WebSocket) {
    try {
      const friendIds = await getFriendIds(userId)
      const onlineMap = await checkFriendsOnline(friendIds)
      for (const friendId of friendIds) {
        if (onlineMap.get(friendId) && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'presence.online', payload: { user_id: friendId } }))
        }
      }
    } catch (err) {
      fastify.log.error(err)
    }
  }

  fastify.server.on('upgrade', (request: IncomingMessage, socket, head) => {
    const url = new URL(request.url ?? '', 'http://localhost')
    if (url.pathname !== '/ws') {
      socket.write('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
      socket.destroy()
      return
    }

    const token = url.searchParams.get('token')
    if (!token) {
      socket.write('HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
      socket.destroy()
      return
    }

    const secret = process.env['JWT_SECRET']!
    let userId: number
    try {
      const decoded = jwt.verify(token, secret) as { id: number }
      if (typeof decoded.id !== 'number') throw new Error('Invalid payload')
      userId = decoded.id
    } catch {
      socket.write('HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
      socket.destroy()
      return
    }

    userIdMap.set(request, userId)
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request)
    })
  })

  wss.on('connection', (ws: WebSocket, request: IncomingMessage) => {
    const userId = userIdMap.get(request)!
    const socketId = crypto.randomUUID()
    wsSocketIds.set(ws, socketId)

    if (!wsConnections.has(userId)) {
      wsConnections.set(userId, new Set())
    }
    const sockets = wsConnections.get(userId)!
    sockets.add(ws)

    registerPresence(userId, socketId)
    sendPresenceSnapshot(userId, ws).catch((err: unknown) => fastify.log.error(err))

    ws.on('message', (data) => {
      void (async () => {
        try {
          const msg = JSON.parse(data.toString()) as { type: string; conversation_id: number }
          if (msg.type !== 'typing.start' && msg.type !== 'typing.stop') return

          // Verify sender is a member and get the other member
          const result = await fastify.pool.query(
            `SELECT cm2.user_id AS recipient_id
             FROM conversation_members cm1
             JOIN conversation_members cm2 ON cm1.conversation_id = cm2.conversation_id
             WHERE cm1.conversation_id = $1 AND cm1.user_id = $2 AND cm2.user_id != $2`,
            [msg.conversation_id, userId]
          )
          if (result.rowCount === 0) return

          const recipientId = result.rows[0].recipient_id as number
          fastify.broadcast(recipientId, {
            type: msg.type,
            payload: { conversation_id: msg.conversation_id, user_id: userId },
          })
        } catch (err) {
          fastify.log.error(err)
        }
      })()
    })

    ws.on('close', () => {
      const sid = wsSocketIds.get(ws)
      wsSocketIds.delete(ws)
      sockets.delete(ws)
      if (sockets.size === 0) wsConnections.delete(userId)

      if (sid) {
        const disconnectTask = fastify.redis.pub.presenceDisconnect(
          presenceKey(userId), memberKey(sid)
        ).then(async (becameOffline) => {
          if (becameOffline === 1) {
            await broadcastPresence(userId, 'presence.offline')
          }
        }).catch((err: unknown) => {
          fastify.log.error(err)
        }).finally(() => {
          pendingPresenceCloseTasks.delete(disconnectTask)
        })
        pendingPresenceCloseTasks.add(disconnectTask)
      }
    })
  })

  // ioredis fires 'ready' on initial connect AND every reconnect.
  // By the time wsPlugin runs, redisPlugin has already awaited pub.connect(),
  // so the initial 'ready' has already fired. Every 'ready' we see is a reconnect.
  fastify.redis.pub.on('ready', () => {
    for (const [userId, socks] of wsConnections.entries()) {
      for (const ws of socks) {
        const sid = wsSocketIds.get(ws)
        if (sid) registerPresence(userId, sid)
      }
    }
  })

  const HEARTBEAT_INTERVAL = 30_000
  const heartbeatTimer = setInterval(async () => {
    try {
      const pipeline = fastify.redis.pub.pipeline()
      for (const [userId, socks] of wsConnections.entries()) {
        for (const ws of socks) {
          const sid = wsSocketIds.get(ws)
          if (sid) {
            pipeline.presenceHeartbeat(presenceKey(userId), memberKey(sid), LEASE_MS)
          }
        }
      }
      await pipeline.exec()
    } catch (err) {
      fastify.log.error(err, 'presence heartbeat error')
    }
  }, HEARTBEAT_INTERVAL)

  const SWEEP_INTERVAL = 30_000
  const SWEEP_LOCK_KEY = 'presence:sweep:lock'
  const SWEEP_LOCK_TTL = 10_000
  const sweepTimer = setInterval(async () => {
    try {
      const acquired = await fastify.redis.pub.set(
        SWEEP_LOCK_KEY, instanceId, 'PX', SWEEP_LOCK_TTL, 'NX'
      )
      if (!acquired) return

      let cursor = '0'
      do {
        const [nextCursor, keys] = await fastify.redis.pub.scan(
          cursor, 'MATCH', 'presence:*', 'COUNT', 100
        )
        cursor = nextCursor

        const validKeys = keys.filter((k) => k !== SWEEP_LOCK_KEY)
        if (validKeys.length === 0) continue

        const pipeline = fastify.redis.pub.pipeline()
        for (const key of validKeys) {
          pipeline.presenceSweepKey(key)
        }
        const results = await pipeline.exec()

        for (let i = 0; i < validKeys.length; i++) {
          if (results?.[i]?.[1] === 1) {
            const userId = parseInt(validKeys[i].split(':')[1])
            await broadcastPresence(userId, 'presence.offline')
          }
        }
      } while (cursor !== '0')
    } catch (err) {
      fastify.log.error(err, 'presence sweep error')
    }
  }, SWEEP_INTERVAL)

  fastify.addHook('onClose', async () => {
    clearInterval(heartbeatTimer)
    clearInterval(sweepTimer)
    for (const client of wss.clients) {
      client.terminate()
    }
    await new Promise<void>((resolve) => wss.close(() => resolve()))
    // 等所有 close 触发的 presence 清理收尾，避免 Redis 先断开导致停机边沿丢失。
    if (pendingPresenceCloseTasks.size > 0) {
      await Promise.allSettled([...pendingPresenceCloseTasks])
    }
  })
})
