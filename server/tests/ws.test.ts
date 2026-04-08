import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach, vi } from 'vitest'
import WebSocket from 'ws'
import type { AddressInfo } from 'net'
import { getApp, truncateAll, registerUser } from './helpers.js'
import type { App } from './helpers.js'

type UserInfo = { token: string; user: { id: number; username: string; email: string } }

async function setupFriends(app: App): Promise<{ alice: UserInfo; bob: UserInfo }> {
  const alice = await registerUser(app)
  const bob = await registerUser(app, { username: 'bob', email: 'bob@test.com', password: 'password123' })
  const reqRes = await app.inject({
    method: 'POST',
    url: '/api/friend-requests',
    headers: { authorization: `Bearer ${alice.token}` },
    payload: { recipient_id: bob.user.id },
  })
  await app.inject({
    method: 'PUT',
    url: `/api/friend-requests/${reqRes.json<{ id: number }>().id}`,
    headers: { authorization: `Bearer ${bob.token}` },
    payload: { status: 'accepted' },
  })
  return { alice, bob }
}

function connectWs(port: number, token: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${token}`)
    const cleanup = () => {
      clearTimeout(timer)
      ws.off('message', handleMessage)
      ws.off('unexpected-response', handleUnexpectedResponse)
      ws.off('error', handleError)
      ws.off('close', handleClose)
    }
    const handleUnexpectedResponse = () => {
      cleanup()
      reject(new Error('Connection rejected'))
    }
    const handleError = (err: Error) => {
      cleanup()
      reject(err)
    }
    const handleClose = () => {
      cleanup()
      reject(new Error('Socket closed before connection.ready'))
    }
    const handleMessage = (data: WebSocket.RawData) => {
      let msg: { type?: string }
      try {
        msg = JSON.parse(data.toString()) as { type?: string }
      } catch {
        cleanup()
        reject(new Error('Malformed message before connection.ready'))
        return
      }

      if (msg.type !== 'connection.ready') {
        cleanup()
        reject(new Error(`Expected connection.ready, got ${msg.type ?? 'unknown'}`))
        return
      }

      cleanup()
      resolve(ws)
    }
    const timer = setTimeout(() => {
      cleanup()
      ws.terminate()
      reject(new Error('Timeout waiting for connection.ready'))
    }, 2000)

    ws.on('message', handleMessage)
    ws.once('unexpected-response', handleUnexpectedResponse)
    ws.once('error', handleError)
    ws.once('close', handleClose)
  })
}

function waitForEvent(ws: WebSocket, type: string, timeout = 2000): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      ws.off('message', handler)
      reject(new Error(`Timeout waiting for event: ${type}`))
    }, timeout)
    const handler = (data: WebSocket.RawData) => {
      const msg = JSON.parse(data.toString()) as { type: string; payload: unknown }
      if (msg.type === type) {
        clearTimeout(timer)
        ws.off('message', handler)
        resolve(msg.payload)
      }
    }
    ws.on('message', handler)
  })
}

function cleanConnections(app: App) {
  for (const sockets of app.wsConnections.values()) {
    for (const s of sockets) s.terminate()
  }
  app.wsConnections.clear()
}

async function waitForCondition(
  condition: () => boolean | Promise<boolean>,
  timeout = 2000,
  interval = 25,
) {
  const deadline = Date.now() + timeout
  while (Date.now() < deadline) {
    if (await condition()) return
    await new Promise((resolve) => setTimeout(resolve, interval))
  }
  throw new Error('Timed out waiting for condition')
}

// ─── Auth ─────────────────────────────────────────────────────────────────────

describe('WebSocket auth', () => {
  let app: App
  let port: number

  beforeAll(async () => {
    app = await getApp()
    await app.listen({ port: 0, host: '127.0.0.1' })
    port = (app.server.address() as AddressInfo).port
  })
  afterAll(async () => { await app.close() })
  beforeEach(async () => { cleanConnections(app); await truncateAll(app) })

  it('accepts a valid token', async () => {
    const alice = await registerUser(app)
    const ws = await connectWs(port, alice.token)
    expect(ws.readyState).toBe(WebSocket.OPEN)
    ws.close()
  })

  it('rejects a missing token', async () => {
    const rejected = await new Promise<boolean>((resolve) => {
      const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`)
      ws.once('open', () => { ws.close(); resolve(false) })
      ws.once('unexpected-response', () => resolve(true))
      ws.once('error', () => resolve(true))
    })
    expect(rejected).toBe(true)
  })

  it('rejects an invalid token', async () => {
    const rejected = await new Promise<boolean>((resolve) => {
      const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=invalid.jwt.token`)
      ws.once('open', () => { ws.close(); resolve(false) })
      ws.once('unexpected-response', () => resolve(true))
      ws.once('error', () => resolve(true))
    })
    expect(rejected).toBe(true)
  })
})

// ─── message.new ──────────────────────────────────────────────────────────────

describe('WebSocket message.new', () => {
  let app: App
  let port: number

  beforeAll(async () => {
    app = await getApp()
    await app.listen({ port: 0, host: '127.0.0.1' })
    port = (app.server.address() as AddressInfo).port
  })
  afterAll(async () => { await app.close() })
  beforeEach(async () => { cleanConnections(app); await truncateAll(app) })

  it('delivers message.new to recipient', async () => {
    const { alice, bob } = await setupFriends(app)
    const bobWs = await connectWs(port, bob.token)

    const eventPromise = waitForEvent(bobWs, 'message.new')
    await app.inject({
      method: 'POST',
      url: '/api/messages',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id, body: 'Hello Bob' },
    })

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.body).toBe('Hello Bob')
    expect(payload.sender_id).toBe(alice.user.id)
    bobWs.close()
  })

  it('delivers message.new to sender too', async () => {
    const { alice, bob } = await setupFriends(app)
    const aliceWs = await connectWs(port, alice.token)

    const eventPromise = waitForEvent(aliceWs, 'message.new')
    await app.inject({
      method: 'POST',
      url: '/api/messages',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id, body: 'Hello Bob' },
    })

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.body).toBe('Hello Bob')
    aliceWs.close()
  })

  it('echoes client_temp_id only to the sender websocket payload', async () => {
    const { alice, bob } = await setupFriends(app)
    const aliceWs = await connectWs(port, alice.token)
    const bobWs = await connectWs(port, bob.token)

    const senderEventPromise = waitForEvent(aliceWs, 'message.new')
    const recipientEventPromise = waitForEvent(bobWs, 'message.new')
    await app.inject({
      method: 'POST',
      url: '/api/messages',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id, body: 'Hello Bob', client_temp_id: 'temp-123' },
    })

    const senderPayload = await senderEventPromise as Record<string, unknown>
    const recipientPayload = await recipientEventPromise as Record<string, unknown>
    expect(senderPayload.client_temp_id).toBe('temp-123')
    expect(recipientPayload.client_temp_id).toBeUndefined()
    aliceWs.close()
    bobWs.close()
  })
})

// ─── conversation.updated ─────────────────────────────────────────────────────

describe('WebSocket conversation.updated', () => {
  let app: App
  let port: number

  beforeAll(async () => {
    app = await getApp()
    await app.listen({ port: 0, host: '127.0.0.1' })
    port = (app.server.address() as AddressInfo).port
  })
  afterAll(async () => { await app.close() })
  beforeEach(async () => { cleanConnections(app); await truncateAll(app) })

  it('delivers conversation.updated when user marks read', async () => {
    const { alice, bob } = await setupFriends(app)
    const msgRes = await app.inject({
      method: 'POST',
      url: '/api/messages',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id, body: 'Hi' },
    })
    const convId = msgRes.json<{ conversation_id: number }>().conversation_id
    const messageId = msgRes.json<{ id: number }>().id

    const bobWs = await connectWs(port, bob.token)
    const eventPromise = waitForEvent(bobWs, 'conversation.updated')

    await app.inject({
      method: 'PUT',
      url: `/api/conversations/${convId}/read`,
      headers: { authorization: `Bearer ${bob.token}` },
      payload: { last_read_message_id: messageId },
    })

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.conversation_id).toBe(convId)
    expect(payload.last_read_message_id).toBe(messageId)
    bobWs.close()
  })
})

// ─── Typing ───────────────────────────────────────────────────────────────────

describe('WebSocket typing indicators', () => {
  let app: App
  let port: number

  beforeAll(async () => {
    app = await getApp()
    await app.listen({ port: 0, host: '127.0.0.1' })
    port = (app.server.address() as AddressInfo).port
  })
  afterAll(async () => { await app.close() })
  beforeEach(async () => { cleanConnections(app); await truncateAll(app) })

  it('forwards typing.start to recipient', async () => {
    const { alice, bob } = await setupFriends(app)
    // Create a conversation first
    const msgRes = await app.inject({
      method: 'POST',
      url: '/api/messages',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id, body: 'Hi' },
    })
    const convId = msgRes.json<{ conversation_id: number }>().conversation_id

    const aliceWs = await connectWs(port, alice.token)
    const bobWs = await connectWs(port, bob.token)

    const eventPromise = waitForEvent(bobWs, 'typing.start')
    aliceWs.send(JSON.stringify({ type: 'typing.start', conversation_id: convId }))

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.conversation_id).toBe(convId)
    expect(payload.user_id).toBe(alice.user.id)

    aliceWs.close()
    bobWs.close()
  })

  it('forwards typing.stop to recipient', async () => {
    const { alice, bob } = await setupFriends(app)
    const msgRes = await app.inject({
      method: 'POST',
      url: '/api/messages',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id, body: 'Hi' },
    })
    const convId = msgRes.json<{ conversation_id: number }>().conversation_id

    const aliceWs = await connectWs(port, alice.token)
    const bobWs = await connectWs(port, bob.token)

    const eventPromise = waitForEvent(bobWs, 'typing.stop')
    aliceWs.send(JSON.stringify({ type: 'typing.stop', conversation_id: convId }))

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.user_id).toBe(alice.user.id)

    aliceWs.close()
    bobWs.close()
  })

  it('ignores typing from non-member', async () => {
    const { alice, bob } = await setupFriends(app)
    const carol = await registerUser(app, { username: 'carol', email: 'carol@test.com', password: 'password123' })
    const msgRes = await app.inject({
      method: 'POST',
      url: '/api/messages',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id, body: 'Hi' },
    })
    const convId = msgRes.json<{ conversation_id: number }>().conversation_id

    // Carol is not a member of alice+bob's conversation
    const carolWs = await connectWs(port, carol.token)
    const bobWs = await connectWs(port, bob.token)

    // Carol sends typing — bob should NOT receive it
    carolWs.send(JSON.stringify({ type: 'typing.start', conversation_id: convId }))

    await expect(waitForEvent(bobWs, 'typing.start', 500)).rejects.toThrow('Timeout')

    carolWs.close()
    bobWs.close()
  })
})

// ─── Presence ─────────────────────────────────────────────────────────────────

describe('WebSocket presence', () => {
  let app: App
  let port: number

  beforeAll(async () => {
    app = await getApp()
    await app.listen({ port: 0, host: '127.0.0.1' })
    port = (app.server.address() as AddressInfo).port
  })
  afterAll(async () => { await app.close() })
  beforeEach(async () => { cleanConnections(app); await truncateAll(app) })

  it('sends snapshot of already-online friends to newcomer', async () => {
    const { alice, bob } = await setupFriends(app)
    // Bob connects first
    const bobWs = await connectWs(port, bob.token)

    // Alice connects second and should immediately receive presence.online for Bob
    const aliceWs = await connectWs(port, alice.token)
    const payload = await waitForEvent(aliceWs, 'presence.online') as Record<string, unknown>
    expect(payload.user_id).toBe(bob.user.id)

    aliceWs.close()
    bobWs.close()
  })

  it('sends presence.online to friends when user connects', async () => {
    const { alice, bob } = await setupFriends(app)
    const bobWs = await connectWs(port, bob.token)

    const eventPromise = waitForEvent(bobWs, 'presence.online')
    const aliceWs = await connectWs(port, alice.token)

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.user_id).toBe(alice.user.id)

    aliceWs.close()
    bobWs.close()
  })

  it('sends presence.offline to friends when user disconnects', async () => {
    const { alice, bob } = await setupFriends(app)
    const bobWs = await connectWs(port, bob.token)

    // Wait for alice's online event before disconnecting
    const onlinePromise = waitForEvent(bobWs, 'presence.online')
    const aliceWs = await connectWs(port, alice.token)
    await onlinePromise

    const offlinePromise = waitForEvent(bobWs, 'presence.offline')
    aliceWs.close()

    const payload = await offlinePromise as Record<string, unknown>
    expect(payload.user_id).toBe(alice.user.id)

    bobWs.close()
  })

  it('does not send presence.offline if user still has another open connection', async () => {
    const { alice, bob } = await setupFriends(app)
    const bobWs = await connectWs(port, bob.token)

    // Alice opens two connections
    const aliceWs1 = await connectWs(port, alice.token)
    const aliceWs2 = await connectWs(port, alice.token)

    // Close one of alice's connections
    aliceWs1.close()

    // Bob should NOT receive presence.offline since alice still has aliceWs2
    await expect(waitForEvent(bobWs, 'presence.offline', 500)).rejects.toThrow('Timeout')

    aliceWs2.close()
    bobWs.close()
  })

  it('does not send presence events to non-friends', async () => {
    const alice = await registerUser(app)
    const carol = await registerUser(app, { username: 'carol', email: 'carol@test.com', password: 'password123' })
    // alice and carol are NOT friends
    const carolWs = await connectWs(port, carol.token)
    const aliceWs = await connectWs(port, alice.token)

    await expect(waitForEvent(carolWs, 'presence.online', 500)).rejects.toThrow('Timeout')

    carolWs.close()
    aliceWs.close()
  })
})

describe('WebSocket presence recovery', () => {
  let app: App
  let port: number

  beforeEach(async () => {
    app = await getApp()
    await app.listen({ port: 0, host: '127.0.0.1' })
    port = (app.server.address() as AddressInfo).port
    await truncateAll(app)
    await app.redis.pub.flushdb()
  })

  afterEach(async () => {
    if (!app) return
    if (app.server.listening) {
      cleanConnections(app)
      await app.close()
    }
  })

  it('re-registers active sockets and re-broadcasts presence.online after Redis data loss recovery', async () => {
    const { alice, bob } = await setupFriends(app)
    const bobWs = await connectWs(port, bob.token)

    const initialOnlinePromise = waitForEvent(bobWs, 'presence.online')
    const aliceWs = await connectWs(port, alice.token)
    await initialOnlinePromise

    await app.redis.pub.flushdb()
    await waitForCondition(async () => {
      const [aliceOnline, bobOnline] = await Promise.all([
        app.redis.pub.presenceCheck(`presence:${alice.user.id}`),
        app.redis.pub.presenceCheck(`presence:${bob.user.id}`),
      ])
      return aliceOnline === 0 && bobOnline === 0
    })

    const recoveredOnlinePromise = waitForEvent(bobWs, 'presence.online', 5000)
    // 用 ready 事件触发恢复路径，避免在测试里真的重启 Docker Redis。
    app.redis.pub.emit('ready')

    const payload = await recoveredOnlinePromise as Record<string, unknown>
    expect(payload.user_id).toBe(alice.user.id)

    await waitForCondition(async () => {
      const [aliceOnline, bobOnline] = await Promise.all([
        app.redis.pub.presenceCheck(`presence:${alice.user.id}`),
        app.redis.pub.presenceCheck(`presence:${bob.user.id}`),
      ])
      return aliceOnline === 1 && bobOnline === 1
    })

    aliceWs.close()
    bobWs.close()
  })

  it('broadcasts presence.offline when the server terminates the last local socket and a friend stays online elsewhere', async () => {
    const { alice, bob } = await setupFriends(app)
    const broadcastSpy = vi.spyOn(app, 'broadcast')

    // 用一个“远端实例”的租约模拟仍在线的好友，避免单实例停机时观察者也一起断掉。
    await app.redis.pub.presenceConnect(`presence:${bob.user.id}`, 'remote-instance:socket-1', 60_000)

    const aliceWs = await connectWs(port, alice.token)
    await waitForCondition(async () => {
      return (await app.redis.pub.presenceCheck(`presence:${alice.user.id}`)) === 1
    })

    cleanConnections(app)

    await waitForCondition(() => {
      return broadcastSpy.mock.calls.some(([targetUserId, event]) => {
        if (targetUserId !== bob.user.id) return false
        if (typeof event !== 'object' || event === null) return false

        const { type, payload } = event as {
          type?: string
          payload?: { user_id?: number }
        }
        return type === 'presence.offline' && payload?.user_id === alice.user.id
      })
    }, 5000)
  })
})

// ─── Friend request events ──────────────────────────────────────────────────

describe('WebSocket friend_request events', () => {
  let app: App
  let port: number

  beforeAll(async () => {
    app = await getApp()
    await app.listen({ port: 0, host: '127.0.0.1' })
    port = (app.server.address() as AddressInfo).port
  })
  afterAll(async () => { await app.close() })
  beforeEach(async () => { cleanConnections(app); await truncateAll(app) })

  it('delivers friend_request.new to recipient with sender info', async () => {
    const alice = await registerUser(app)
    const bob = await registerUser(app, { username: 'bob', email: 'bob@test.com', password: 'password123' })
    const bobWs = await connectWs(port, bob.token)

    const eventPromise = waitForEvent(bobWs, 'friend_request.new')
    await app.inject({
      method: 'POST',
      url: '/api/friend-requests',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id },
    })

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.sender_id).toBe(alice.user.id)
    expect(payload.recipient_id).toBe(bob.user.id)
    expect(payload.status).toBe('pending')
    // 接收方看到的是发送者（alice）的用户信息
    expect(payload.username).toBe('alice')
    bobWs.close()
  })

  it('delivers friend_request.new to sender with recipient info (multi-tab)', async () => {
    const alice = await registerUser(app)
    const bob = await registerUser(app, { username: 'bob', email: 'bob@test.com', password: 'password123' })
    const aliceWs = await connectWs(port, alice.token)

    const eventPromise = waitForEvent(aliceWs, 'friend_request.new')
    await app.inject({
      method: 'POST',
      url: '/api/friend-requests',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id },
    })

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.sender_id).toBe(alice.user.id)
    expect(payload.recipient_id).toBe(bob.user.id)
    // 发送方看到的是接收者（bob）的用户信息，与 /friend-requests/sent 一致
    expect(payload.username).toBe('bob')
    aliceWs.close()
  })

  it('delivers friend_request.accepted to sender with responder info', async () => {
    const alice = await registerUser(app)
    const bob = await registerUser(app, { username: 'bob', email: 'bob@test.com', password: 'password123' })

    const reqRes = await app.inject({
      method: 'POST',
      url: '/api/friend-requests',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id },
    })
    const requestId = reqRes.json<{ id: number }>().id

    const aliceWs = await connectWs(port, alice.token)
    const eventPromise = waitForEvent(aliceWs, 'friend_request.accepted')

    await app.inject({
      method: 'PUT',
      url: `/api/friend-requests/${requestId}`,
      headers: { authorization: `Bearer ${bob.token}` },
      payload: { status: 'accepted' },
    })

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.id).toBe(requestId)
    expect(payload.status).toBe('accepted')
    // 原始发送方（alice）看到的是操作方（bob）的用户信息
    expect(payload.username).toBe('bob')
    aliceWs.close()
  })

  it('delivers friend_request.accepted to acceptor with sender info (multi-tab)', async () => {
    const alice = await registerUser(app)
    const bob = await registerUser(app, { username: 'bob', email: 'bob@test.com', password: 'password123' })

    const reqRes = await app.inject({
      method: 'POST',
      url: '/api/friend-requests',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id },
    })
    const requestId = reqRes.json<{ id: number }>().id

    const bobWs = await connectWs(port, bob.token)
    const eventPromise = waitForEvent(bobWs, 'friend_request.accepted')

    await app.inject({
      method: 'PUT',
      url: `/api/friend-requests/${requestId}`,
      headers: { authorization: `Bearer ${bob.token}` },
      payload: { status: 'accepted' },
    })

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.id).toBe(requestId)
    expect(payload.status).toBe('accepted')
    // 操作方（bob）看到的是原始发送方（alice）的用户信息
    expect(payload.username).toBe('alice')
    bobWs.close()
  })

  it('delivers friend_request.declined to sender with responder info', async () => {
    const alice = await registerUser(app)
    const bob = await registerUser(app, { username: 'bob', email: 'bob@test.com', password: 'password123' })

    const reqRes = await app.inject({
      method: 'POST',
      url: '/api/friend-requests',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id },
    })
    const requestId = reqRes.json<{ id: number }>().id

    const aliceWs = await connectWs(port, alice.token)
    const eventPromise = waitForEvent(aliceWs, 'friend_request.declined')

    await app.inject({
      method: 'PUT',
      url: `/api/friend-requests/${requestId}`,
      headers: { authorization: `Bearer ${bob.token}` },
      payload: { status: 'declined' },
    })

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.id).toBe(requestId)
    expect(payload.status).toBe('declined')
    // 原始发送方（alice）看到的是操作方（bob）的用户信息
    expect(payload.username).toBe('bob')
    aliceWs.close()
  })

  it('delivers friend_request.declined to decliner with sender info (multi-tab)', async () => {
    const alice = await registerUser(app)
    const bob = await registerUser(app, { username: 'bob', email: 'bob@test.com', password: 'password123' })

    const reqRes = await app.inject({
      method: 'POST',
      url: '/api/friend-requests',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id },
    })
    const requestId = reqRes.json<{ id: number }>().id

    const bobWs = await connectWs(port, bob.token)
    const eventPromise = waitForEvent(bobWs, 'friend_request.declined')

    await app.inject({
      method: 'PUT',
      url: `/api/friend-requests/${requestId}`,
      headers: { authorization: `Bearer ${bob.token}` },
      payload: { status: 'declined' },
    })

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.id).toBe(requestId)
    expect(payload.status).toBe('declined')
    // 操作方（bob）看到的是原始发送方（alice）的用户信息
    expect(payload.username).toBe('alice')
    bobWs.close()
  })
})
