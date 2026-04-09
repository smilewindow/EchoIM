import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import WebSocket from 'ws'
import type { AddressInfo } from 'net'
import {
  getApp, truncateAll, flushRedis, registerUser,
  setupFriends, connectWs, waitForEvent, waitForCondition,
} from './helpers.js'
import type { App } from './helpers.js'

interface DualApps {
  app1: App; app2: App; port1: number; port2: number
}

async function setupDualApps(): Promise<DualApps> {
  const [app1, app2] = await Promise.all([getApp(), getApp()])
  await Promise.all([
    app1.listen({ port: 0, host: '127.0.0.1' }),
    app2.listen({ port: 0, host: '127.0.0.1' }),
  ])
  const port1 = (app1.server.address() as AddressInfo).port
  const port2 = (app2.server.address() as AddressInfo).port
  await truncateAll(app1)
  await flushRedis(app1)
  return { app1, app2, port1, port2 }
}

async function teardownDualApps(app1: App, app2: App) {
  if (app1?.server?.listening) await app1.close()
  if (app2?.server?.listening) await app2.close()
}

// ─── Cross-instance broadcast ───────────────────────────────────────────────

describe('cross-instance broadcast', () => {
  let app1: App, app2: App, port1: number, port2: number

  beforeEach(async () => { ({ app1, app2, port1, port2 } = await setupDualApps()) })
  afterEach(async () => { await teardownDualApps(app1, app2) })

  it('delivers message.new across instances', async () => {
    const { alice, bob } = await setupFriends(app1)
    const aliceWs = await connectWs(port1, alice.token)
    const bobWs = await connectWs(port2, bob.token)

    const eventPromise = waitForEvent(bobWs, 'message.new')
    await app1.inject({
      method: 'POST',
      url: '/api/messages',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id, body: 'Cross-instance hello' },
    })

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.body).toBe('Cross-instance hello')
    expect(payload.sender_id).toBe(alice.user.id)

    aliceWs.close()
    bobWs.close()
  })

  it('delivers message.new to sender on different instance', async () => {
    const { alice, bob } = await setupFriends(app1)
    const aliceWs = await connectWs(port2, alice.token)

    const eventPromise = waitForEvent(aliceWs, 'message.new')
    await app1.inject({
      method: 'POST',
      url: '/api/messages',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id, body: 'Echo to other instance' },
    })

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.body).toBe('Echo to other instance')

    aliceWs.close()
  })
})

// ─── Cross-instance presence ────────────────────────────────────────────────

describe('cross-instance presence', () => {
  let app1: App, app2: App, port1: number, port2: number

  beforeEach(async () => { ({ app1, app2, port1, port2 } = await setupDualApps()) })
  afterEach(async () => { await teardownDualApps(app1, app2) })

  it('sends presence.online across instances', async () => {
    const { alice, bob } = await setupFriends(app1)
    const bobWs = await connectWs(port2, bob.token)

    const onlinePromise = waitForEvent(bobWs, 'presence.online')
    const aliceWs = await connectWs(port1, alice.token)

    const payload = await onlinePromise as Record<string, unknown>
    expect(payload.user_id).toBe(alice.user.id)

    aliceWs.close()
    bobWs.close()
  })

  it('sends presence.offline across instances when user disconnects', async () => {
    const { alice, bob } = await setupFriends(app1)
    const bobWs = await connectWs(port2, bob.token)

    const onlinePromise = waitForEvent(bobWs, 'presence.online')
    const aliceWs = await connectWs(port1, alice.token)
    await onlinePromise

    const offlinePromise = waitForEvent(bobWs, 'presence.offline')
    aliceWs.close()

    const payload = await offlinePromise as Record<string, unknown>
    expect(payload.user_id).toBe(alice.user.id)

    bobWs.close()
  })

  it('sends presence snapshot to newcomer with friends on other instances', async () => {
    const { alice, bob } = await setupFriends(app1)

    // Block broadcast path on app1 so Alice→Bob presence.online can only
    // arrive via sendPresenceSnapshot() (direct ws.send), not Pub/Sub.
    const originalBroadcast = app1.broadcast.bind(app1)
    const broadcastSpy = vi.spyOn(app1, 'broadcast').mockImplementation(
      async (userId: number, event: { type: string; payload: unknown }) => {
        const { user_id } = event.payload as { user_id?: number }
        if (userId === bob.user.id && event.type === 'presence.online' && user_id === alice.user.id) {
          return
        }
        return originalBroadcast(userId, event)
      }
    )

    const aliceWs = await connectWs(port1, alice.token)
    await waitForCondition(async () => {
      return (await app1.redis.pub.presenceCheck(`presence:${alice.user.id}`)) === 1
    })

    const bobWs = await connectWs(port2, bob.token)
    const payload = await waitForEvent(bobWs, 'presence.online') as Record<string, unknown>
    expect(payload.user_id).toBe(alice.user.id)

    broadcastSpy.mockRestore()
    aliceWs.close()
    bobWs.close()
  })
})

// ─── Subscribe failure cleanup ──────────────────────────────────────────────

describe('subscribe failure / early disconnect cleanup', () => {
  let app: App
  let port: number

  beforeEach(async () => {
    app = await getApp()
    await app.listen({ port: 0, host: '127.0.0.1' })
    port = (app.server.address() as AddressInfo).port
    await truncateAll(app)
    await flushRedis(app)
  })

  afterEach(async () => {
    if (app?.server?.listening) await app.close()
  })

  it('cleans up userSubStates when subscribe throws', async () => {
    const alice = await registerUser(app)
    const subscribeSpy = vi.spyOn(app.redis.sub, 'subscribe').mockRejectedValueOnce(new Error('mock subscribe failure'))

    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${alice.token}`)
    await new Promise<void>((resolve) => {
      ws.on('close', () => resolve())
      setTimeout(() => resolve(), 3000)
    })

    await waitForCondition(() => !app.wsUserSubStates.has(alice.user.id), 2000)

    expect(app.wsConnections.has(alice.user.id)).toBe(false)
    expect(app.wsUserSubStates.has(alice.user.id)).toBe(false)

    subscribeSpy.mockRestore()
  })

  it('recovers and accepts new connections after subscribe failure', async () => {
    const alice = await registerUser(app)
    vi.spyOn(app.redis.sub, 'subscribe').mockRejectedValueOnce(new Error('mock subscribe failure'))

    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${alice.token}`)
    await new Promise<void>((resolve) => {
      ws.on('close', () => resolve())
      setTimeout(() => resolve(), 3000)
    })

    await waitForCondition(() => !app.wsUserSubStates.has(alice.user.id), 2000)

    const ws2 = await connectWs(port, alice.token)
    expect(ws2.readyState).toBe(WebSocket.OPEN)
    expect(app.wsUserSubStates.has(alice.user.id)).toBe(true)
    expect(app.wsUserSubStates.get(alice.user.id)!.status).toBe('subscribed')

    ws2.close()
  })

  it('cleans up userSubStates when client disconnects before initialized', async () => {
    const alice = await registerUser(app)

    // Delay subscribe so close fires while initialized is still false
    const originalSubscribe = app.redis.sub.subscribe.bind(app.redis.sub)
    const slowSubscribeSpy = vi.spyOn(app.redis.sub, 'subscribe').mockImplementation(
      async (...args: Parameters<typeof app.redis.sub.subscribe>) => {
        await new Promise((resolve) => setTimeout(resolve, 200))
        return originalSubscribe(...args)
      }
    )

    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${alice.token}`)
    await new Promise<void>((resolve) => {
      ws.on('open', () => {
        ws.close()
        resolve()
      })
      ws.on('error', () => resolve())
    })

    await waitForCondition(() => !app.wsUserSubStates.has(alice.user.id), 3000)

    expect(app.wsConnections.has(alice.user.id)).toBe(false)
    expect(app.wsUserSubStates.has(alice.user.id)).toBe(false)

    slowSubscribeSpy.mockRestore()
  })
})

// ─── Cross-instance typing ──────────────────────────────────────────────────

describe('cross-instance typing indicators', () => {
  let app1: App, app2: App, port1: number, port2: number

  beforeEach(async () => { ({ app1, app2, port1, port2 } = await setupDualApps()) })
  afterEach(async () => { await teardownDualApps(app1, app2) })

  it('forwards typing.start across instances', async () => {
    const { alice, bob } = await setupFriends(app1)
    const msgRes = await app1.inject({
      method: 'POST',
      url: '/api/messages',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id, body: 'Hi' },
    })
    const convId = msgRes.json<{ conversation_id: number }>().conversation_id

    const aliceWs = await connectWs(port1, alice.token)
    const bobWs = await connectWs(port2, bob.token)

    const eventPromise = waitForEvent(bobWs, 'typing.start')
    aliceWs.send(JSON.stringify({ type: 'typing.start', conversation_id: convId }))

    const payload = await eventPromise as Record<string, unknown>
    expect(payload.conversation_id).toBe(convId)
    expect(payload.user_id).toBe(alice.user.id)

    aliceWs.close()
    bobWs.close()
  })
})
