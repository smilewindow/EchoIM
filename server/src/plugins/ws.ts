import fp from 'fastify-plugin'
import { WebSocketServer, WebSocket } from 'ws'
import crypto from 'node:crypto'
import type { IncomingMessage } from 'http'
import type { FastifyInstance } from 'fastify'
import jwt from 'jsonwebtoken'

declare module 'fastify' {
  interface FastifyInstance {
    broadcast: (userId: number, event: { type: string; payload: unknown }) => Promise<void>
    wsConnections: Map<number, Set<WebSocket>>
    /** Exposed for testing — tracks per-user subscription lifecycle */
    wsUserSubStates: Map<number, UserSubState>
  }
}

export interface UserSubState {
  status: 'subscribing' | 'subscribed' | 'unsubscribing' | 'unsubscribed'
  readySockets: Set<WebSocket>
  pendingInits: number
  queue: Promise<void>
}

const instanceId = crypto.randomUUID()
const presenceKey = (userId: number) => `presence:${userId}`
const memberKey = (socketId: string) => `${instanceId}:${socketId}`
const CONNECTION_READY_MSG = JSON.stringify({ type: 'connection.ready' })

export default fp(async function wsPlugin(fastify: FastifyInstance) {
  fastify.log.info({ instanceId }, 'ws plugin initialized')

  const wsConnections = new Map<number, Set<WebSocket>>()
  const userIdMap = new WeakMap<IncomingMessage, number>()
  const wsSocketIds = new Map<WebSocket, string>()
  const pendingPresenceCloseTasks = new Set<Promise<void>>()
  const userSubStates = new Map<number, UserSubState>()
  const wss = new WebSocketServer({ noServer: true })
  const LEASE_MS = 60_000
  let closing = false

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

  function enqueueSubOp(state: UserSubState, op: () => Promise<void>): Promise<void> {
    state.queue = state.queue.then(op, op)
    return state.queue
  }

  async function tryUnsubscribeAndReclaim(userId: number, state: UserSubState) {
    if (state.readySockets.size > 0 || state.pendingInits > 0) return

    if (state.status === 'subscribed' || state.status === 'subscribing') {
      state.status = 'unsubscribing'
      try {
        await fastify.redis.sub.unsubscribe(`user:${userId}`)
      } catch (err) {
        fastify.log.error(err, `failed to unsubscribe user:${userId}`)
      }
      state.status = 'unsubscribed'
    }

    if (
      userSubStates.get(userId) === state &&
      state.readySockets.size === 0 &&
      state.pendingInits === 0 &&
      state.status === 'unsubscribed'
    ) {
      userSubStates.delete(userId)
    }
  }

  fastify.decorate('wsConnections', wsConnections)
  fastify.decorate('wsUserSubStates', userSubStates)

  fastify.decorate('broadcast', async function (userId: number, event: { type: string; payload: unknown }) {
    await fastify.redis.pub.publish(`user:${userId}`, JSON.stringify(event))
  })

  fastify.redis.sub.on('message', (channel: string, message: string) => {
    const userId = parseInt(channel.split(':')[1])
    const sockets = wsConnections.get(userId)
    if (!sockets) return
    for (const socket of sockets) {
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(message)
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
      onlineMap.set(friendIds[i], results?.[i]?.[1] === 1)
    }
    return onlineMap
  }

  async function broadcastPresence(userId: number, type: 'presence.online' | 'presence.offline') {
    try {
      const friendIds = await getFriendIds(userId)
      const nowOnline = (await fastify.redis.pub.presenceCheck(presenceKey(userId))) === 1
      if (type === 'presence.online' && !nowOnline) return
      if (type === 'presence.offline' && nowOnline) return

      const onlineMap = await checkFriendsOnline(friendIds)
      const publishTasks: Promise<void>[] = []
      for (const friendId of friendIds) {
        if (onlineMap.get(friendId)) {
          publishTasks.push(
            fastify.broadcast(friendId, { type, payload: { user_id: userId } })
          )
        }
      }
      await Promise.all(publishTasks)
    } catch (err) {
      fastify.log.error(err)
    }
  }

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
    if (closing) {
      socket.write('HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
      socket.destroy()
      return
    }

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

  wss.on('connection', async (ws: WebSocket, request: IncomingMessage) => {
    const userId = userIdMap.get(request)!
    const socketId = crypto.randomUUID()
    let initialized = false
    const state = getOrCreateSubState(userId)

    // Immediately increment pendingInits before any await
    state.pendingInits++

    // Register close handler immediately — owns pendingInits decrement when !initialized
    ws.on('close', async () => {
      fastify.log.info(
        { userId, socketId, instanceId, initialized },
        'ws disconnected'
      )
      // Snapshot closing flag at handler entry to avoid race with onClose hook.
      // If closing was already true when this fires, the onClose hook handles
      // presence cleanup; this handler only does structural bookkeeping.
      const wasClosing = closing
      wsSocketIds.delete(ws)
      if (!initialized) {
        state.pendingInits--
        await enqueueSubOp(state, async () => {
          await tryUnsubscribeAndReclaim(userId, state)
        })
        return
      }
      // Normal disconnect cleanup
      state.readySockets.delete(ws)
      const localSockets = wsConnections.get(userId)
      if (localSockets) {
        localSockets.delete(ws)
        if (localSockets.size === 0) wsConnections.delete(userId)
      }
      // Presence offline — fire before enqueueSubOp to avoid latency from unsubscribe
      const disconnectTask = fastify.redis.pub.presenceDisconnect(
        presenceKey(userId), memberKey(socketId)
      ).then(async (becameOffline) => {
        if (becameOffline === 1 && !wasClosing) {
          await broadcastPresence(userId, 'presence.offline')
        }
      }).catch((err: unknown) => {
        fastify.log.error(err)
      }).finally(() => {
        pendingPresenceCloseTasks.delete(disconnectTask)
      })
      pendingPresenceCloseTasks.add(disconnectTask)
      // Unsubscribe channel if no more local sockets
      await enqueueSubOp(state, async () => {
        await tryUnsubscribeAndReclaim(userId, state)
      })
    })

    // Register message handler before async subscribe so incoming WS
    // messages aren't dropped during initialization.
    ws.on('message', (data) => {
      void (async () => {
        try {
          const msg = JSON.parse(data.toString()) as { type: string; conversation_id: number }
          if (msg.type !== 'typing.start' && msg.type !== 'typing.stop') return

          const result = await fastify.pool.query(
            `SELECT cm2.user_id AS recipient_id
             FROM conversation_members cm1
             JOIN conversation_members cm2 ON cm1.conversation_id = cm2.conversation_id
             WHERE cm1.conversation_id = $1 AND cm1.user_id = $2 AND cm2.user_id != $2`,
            [msg.conversation_id, userId]
          )
          if (result.rowCount === 0) return

          const recipientId = result.rows[0].recipient_id as number
          await fastify.broadcast(recipientId, {
            type: msg.type,
            payload: { conversation_id: msg.conversation_id, user_id: userId },
          })
        } catch (err) {
          fastify.log.error(err)
        }
      })()
    })

    try {
      wsSocketIds.set(ws, socketId)

      // Serialize subscribe via queue
      await enqueueSubOp(state, async () => {
        if (state.status === 'unsubscribed' || state.status === 'unsubscribing') {
          state.status = 'subscribing'
          try {
            await fastify.redis.sub.subscribe(`user:${userId}`)
            state.status = 'subscribed'
          } catch (err) {
            state.status = 'unsubscribed'
            throw err
          }
        }
      })

      // Client may have disconnected while awaiting subscribe
      if (ws.readyState !== WebSocket.OPEN) return

      // Transition from pending to ready
      state.pendingInits--
      state.readySockets.add(ws)

      if (!wsConnections.has(userId)) wsConnections.set(userId, new Set())
      wsConnections.get(userId)!.add(ws)

      initialized = true

      fastify.log.info(
        { userId, socketId, instanceId },
        'ws connected'
      )

      ws.send(CONNECTION_READY_MSG)

      // Register presence
      const becameOnline = await fastify.redis.pub.presenceConnect(
        presenceKey(userId),
        memberKey(socketId),
        LEASE_MS
      )
      if (becameOnline === 1) {
        broadcastPresence(userId, 'presence.online')
          .catch((e: unknown) => fastify.log.error(e, 'broadcastPresence failed'))
      }

      await sendPresenceSnapshot(userId, ws)
        .catch((e: unknown) => fastify.log.error(e, 'sendPresenceSnapshot failed'))
    } catch (err) {
      fastify.log.error(err, 'ws connection init failed')
      ws.close()
    }
  })

  // On Redis reconnect, re-register presence for all active connections
  fastify.redis.pub.on('ready', () => {
    for (const [userId, socks] of wsConnections.entries()) {
      for (const ws of socks) {
        const sid = wsSocketIds.get(ws)
        if (sid) {
          fastify.redis.pub.presenceConnect(
            presenceKey(userId), memberKey(sid), LEASE_MS
          ).then((becameOnline) => {
            if (becameOnline === 1) {
              return broadcastPresence(userId, 'presence.online')
            }
          }).catch((err: unknown) => fastify.log.error(err))
        }
      }
    }
    // Re-subscribe channels for all tracked users
    for (const [userId, subState] of userSubStates.entries()) {
      if (subState.readySockets.size > 0 || subState.pendingInits > 0) {
        fastify.redis.sub.subscribe(`user:${userId}`)
          .then(() => { subState.status = 'subscribed' })
          .catch((err: unknown) => fastify.log.error(err, `re-subscribe user:${userId} failed`))
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

  // preClose runs BEFORE server.close(). Without this, server.close() waits
  // for all TCP connections (including upgraded WS) to drain, blocking onClose
  // hooks indefinitely.
  fastify.addHook('preClose', async () => {
    closing = true
    clearInterval(heartbeatTimer)
    clearInterval(sweepTimer)

    // Graceful shutdown: actively clean up presence and broadcast offline
    // before terminating connections. Individual socket close handlers skip
    // offline broadcast when wasClosing=true, so we handle it here.
    const offlineTasks: Promise<void>[] = []
    for (const [userId, sockets] of wsConnections.entries()) {
      for (const ws of sockets) {
        const socketId = wsSocketIds.get(ws)
        if (socketId) {
          offlineTasks.push(
            fastify.redis.pub.presenceDisconnect(
              presenceKey(userId), memberKey(socketId)
            ).then(async (becameOffline) => {
              if (becameOffline === 1) {
                await broadcastPresence(userId, 'presence.offline')
              }
            }).catch((err: unknown) => {
              fastify.log.error(err, 'graceful shutdown presence cleanup failed')
            })
          )
        }
      }
    }
    await Promise.allSettled(offlineTasks)

    // Terminate WS connections so server.close() can complete
    for (const client of wss.clients) {
      client.terminate()
    }
    await new Promise<void>((resolve) => wss.close(() => resolve()))
  })

  fastify.addHook('onClose', async () => {
    // Drain any in-flight disconnect tasks from individual socket close handlers
    if (pendingPresenceCloseTasks.size > 0) {
      await Promise.allSettled([...pendingPresenceCloseTasks])
    }
  })
})
