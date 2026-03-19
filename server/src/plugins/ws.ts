import fp from 'fastify-plugin'
import { WebSocketServer, WebSocket } from 'ws'
import type { IncomingMessage } from 'http'
import type { FastifyInstance } from 'fastify'
import jwt from 'jsonwebtoken'

declare module 'fastify' {
  interface FastifyInstance {
    broadcast: (userId: number, event: { type: string; payload: unknown }) => void
    wsConnections: Map<number, Set<WebSocket>>
  }
}

export default fp(async function wsPlugin(fastify: FastifyInstance) {
  const wsConnections = new Map<number, Set<WebSocket>>()
  const userIdMap = new WeakMap<IncomingMessage, number>()
  const wss = new WebSocketServer({ noServer: true })
  let closing = false

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

  async function broadcastPresence(userId: number, type: 'presence.online' | 'presence.offline') {
    try {
      const result = await fastify.pool.query(
        `SELECT CASE WHEN sender_id = $1 THEN recipient_id ELSE sender_id END AS friend_id
         FROM friend_requests
         WHERE status = 'accepted' AND (sender_id = $1 OR recipient_id = $1)`,
        [userId]
      )
      // Re-check state after the async DB round-trip. A quick disconnect/reconnect can
      // cause the offline query to resolve after a new online query (or vice versa),
      // leaving friends with a stale indicator. Drop the broadcast if state has changed.
      const nowOnline = wsConnections.has(userId)
      if (type === 'presence.online' && !nowOnline) return
      if (type === 'presence.offline' && nowOnline) return

      for (const row of result.rows) {
        const friendId = row.friend_id as number
        if (wsConnections.has(friendId)) {
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
      const result = await fastify.pool.query(
        `SELECT CASE WHEN sender_id = $1 THEN recipient_id ELSE sender_id END AS friend_id
         FROM friend_requests
         WHERE status = 'accepted' AND (sender_id = $1 OR recipient_id = $1)`,
        [userId]
      )
      for (const row of result.rows) {
        const friendId = row.friend_id as number
        if (wsConnections.has(friendId) && ws.readyState === WebSocket.OPEN) {
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

    if (!wsConnections.has(userId)) {
      wsConnections.set(userId, new Set())
    }
    const sockets = wsConnections.get(userId)!
    sockets.add(ws)

    if (sockets.size === 1) {
      broadcastPresence(userId, 'presence.online').catch((err: unknown) => fastify.log.error(err))
    }
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
      sockets.delete(ws)
      if (sockets.size === 0 && wsConnections.has(userId)) {
        wsConnections.delete(userId)
        if (!closing) {
          broadcastPresence(userId, 'presence.offline').catch((err: unknown) => fastify.log.error(err))
        }
      }
    })
  })

  fastify.addHook('onClose', async () => {
    closing = true
    for (const client of wss.clients) {
      client.terminate()
    }
    await new Promise<void>((resolve) => wss.close(() => resolve()))
  })
})
