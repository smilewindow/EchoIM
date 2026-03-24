import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest'
import { getApp, truncateAll, registerUser } from './helpers.js'
import type { App } from './helpers.js'

type UserInfo = { token: string; user: { id: number; username: string; email: string } }

async function sendFriendRequest(app: App, senderToken: string, recipientId: number) {
  return app.inject({
    method: 'POST',
    url: '/api/friend-requests',
    headers: { authorization: `Bearer ${senderToken}` },
    payload: { recipient_id: recipientId },
  })
}

async function acceptFriendRequest(app: App, token: string, requestId: number) {
  return app.inject({
    method: 'PUT',
    url: `/api/friend-requests/${requestId}`,
    headers: { authorization: `Bearer ${token}` },
    payload: { status: 'accepted' },
  })
}

async function setupFriends(app: App): Promise<{ alice: UserInfo; bob: UserInfo }> {
  const alice = await registerUser(app)
  const bob = await registerUser(app, { username: 'bob', email: 'bob@test.com', password: 'password123' })
  const req = await sendFriendRequest(app, alice.token, bob.user.id)
  await acceptFriendRequest(app, bob.token, req.json().id)
  return { alice, bob }
}

async function sendMessage(
  app: App,
  token: string,
  recipient_id: number,
  body: string,
  client_temp_id?: string,
) {
  return app.inject({
    method: 'POST',
    url: '/api/messages',
    headers: { authorization: `Bearer ${token}` },
    payload: client_temp_id ? { recipient_id, body, client_temp_id } : { recipient_id, body },
  })
}

// ─── POST /api/messages ───────────────────────────────────────────────────────

describe('POST /api/messages', () => {
  let app: App

  beforeAll(async () => { app = await getApp() })
  afterAll(async () => { await app.close() })
  beforeEach(async () => { await truncateAll(app) })

  it('sends message between friends and returns 201 with message object', async () => {
    const { alice, bob } = await setupFriends(app)
    const res = await sendMessage(app, alice.token, bob.user.id, 'Hello Bob!')
    expect(res.statusCode).toBe(201)
    const body = res.json()
    expect(body.sender_id).toBe(alice.user.id)
    expect(body.body).toBe('Hello Bob!')
    expect(body.conversation_id).toBeTypeOf('number')
  })

  it('echoes client_temp_id back to the sender response when provided', async () => {
    const { alice, bob } = await setupFriends(app)
    const res = await sendMessage(app, alice.token, bob.user.id, 'Hello Bob!', 'temp-123')
    expect(res.statusCode).toBe(201)
    expect(res.json().client_temp_id).toBe('temp-123')
  })

  it('auto-creates conversation on first message', async () => {
    const { alice, bob } = await setupFriends(app)
    const res = await sendMessage(app, alice.token, bob.user.id, 'First message')
    expect(res.statusCode).toBe(201)
    expect(res.json().conversation_id).toBeTypeOf('number')
  })

  it('reuses existing conversation on subsequent messages', async () => {
    const { alice, bob } = await setupFriends(app)
    const r1 = await sendMessage(app, alice.token, bob.user.id, 'First')
    const r2 = await sendMessage(app, alice.token, bob.user.id, 'Second')
    expect(r1.json().conversation_id).toBe(r2.json().conversation_id)
  })

  it('returns 403 when users are not friends', async () => {
    const alice = await registerUser(app)
    const bob = await registerUser(app, { username: 'bob', email: 'bob@test.com', password: 'password123' })
    const res = await sendMessage(app, alice.token, bob.user.id, 'Hello')
    expect(res.statusCode).toBe(403)
  })

  it('returns 400 for missing body', async () => {
    const { alice, bob } = await setupFriends(app)
    const res = await app.inject({
      method: 'POST',
      url: '/api/messages',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { recipient_id: bob.user.id },
    })
    expect(res.statusCode).toBe(400)
  })

  it('returns 400 for missing recipient_id', async () => {
    const { alice } = await setupFriends(app)
    const res = await app.inject({
      method: 'POST',
      url: '/api/messages',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { body: 'Hello' },
    })
    expect(res.statusCode).toBe(400)
  })

  it('returns 401 when unauthenticated', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/messages',
      payload: { recipient_id: 1, body: 'Hello' },
    })
    expect(res.statusCode).toBe(401)
  })
})

// ─── GET /api/conversations ───────────────────────────────────────────────────

describe('GET /api/conversations', () => {
  let app: App

  beforeAll(async () => { app = await getApp() })
  afterAll(async () => { await app.close() })
  beforeEach(async () => { await truncateAll(app) })

  it('returns conversations sorted by latest message', async () => {
    const { alice, bob } = await setupFriends(app)
    await sendMessage(app, alice.token, bob.user.id, 'Hello')

    const res = await app.inject({
      method: 'GET',
      url: '/api/conversations',
      headers: { authorization: `Bearer ${alice.token}` },
    })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body).toHaveLength(1)
    expect(body[0].last_message_body).toBe('Hello')
  })

  it('includes unread count', async () => {
    const { alice, bob } = await setupFriends(app)
    await sendMessage(app, alice.token, bob.user.id, 'Hey')
    await sendMessage(app, alice.token, bob.user.id, 'What up')

    const res = await app.inject({
      method: 'GET',
      url: '/api/conversations',
      headers: { authorization: `Bearer ${bob.token}` },
    })
    expect(res.statusCode).toBe(200)
    expect(Number(res.json()[0].unread_count)).toBe(2)
  })

  it('includes peer user info', async () => {
    const { alice, bob } = await setupFriends(app)
    await sendMessage(app, alice.token, bob.user.id, 'Hi')

    const res = await app.inject({
      method: 'GET',
      url: '/api/conversations',
      headers: { authorization: `Bearer ${alice.token}` },
    })
    expect(res.statusCode).toBe(200)
    const conv = res.json()[0]
    expect(conv.peer_id).toBe(bob.user.id)
    expect(conv.peer_username).toBe('bob')
  })

  it('returns empty array when no conversations', async () => {
    const alice = await registerUser(app)
    const res = await app.inject({
      method: 'GET',
      url: '/api/conversations',
      headers: { authorization: `Bearer ${alice.token}` },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toHaveLength(0)
  })

  it('unread count decrements after marking read', async () => {
    const { alice, bob } = await setupFriends(app)
    const msgRes = await sendMessage(app, alice.token, bob.user.id, 'Hey')
    const convId = msgRes.json().conversation_id
    const firstMessageId = msgRes.json().id

    await app.inject({
      method: 'PUT',
      url: `/api/conversations/${convId}/read`,
      headers: { authorization: `Bearer ${bob.token}` },
      payload: { last_read_message_id: firstMessageId },
    })

    const res = await app.inject({
      method: 'GET',
      url: '/api/conversations',
      headers: { authorization: `Bearer ${bob.token}` },
    })
    expect(res.statusCode).toBe(200)
    expect(Number(res.json()[0].unread_count)).toBe(0)
  })

  it('does not count sender own messages as unread', async () => {
    const { alice, bob } = await setupFriends(app)
    await sendMessage(app, alice.token, bob.user.id, 'Hello Bob')

    const res = await app.inject({
      method: 'GET',
      url: '/api/conversations',
      headers: { authorization: `Bearer ${alice.token}` },
    })
    expect(res.statusCode).toBe(200)
    expect(Number(res.json()[0].unread_count)).toBe(0)
  })

  it('returns unread_count as a number', async () => {
    const { alice, bob } = await setupFriends(app)
    await sendMessage(app, alice.token, bob.user.id, 'Hey')

    const res = await app.inject({
      method: 'GET',
      url: '/api/conversations',
      headers: { authorization: `Bearer ${bob.token}` },
    })
    expect(res.statusCode).toBe(200)
    expect(typeof res.json()[0].unread_count).toBe('number')
  })

  it('returns 401 when unauthenticated', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/conversations' })
    expect(res.statusCode).toBe(401)
  })
})

// ─── GET /api/conversations/:id/messages ─────────────────────────────────────

describe('GET /api/conversations/:id/messages', () => {
  let app: App

  beforeAll(async () => { app = await getApp() })
  afterAll(async () => { await app.close() })
  beforeEach(async () => { await truncateAll(app) })

  it('returns messages for a conversation (newest first)', async () => {
    const { alice, bob } = await setupFriends(app)
    const r1 = await sendMessage(app, alice.token, bob.user.id, 'First')
    const convId = r1.json().conversation_id
    await sendMessage(app, alice.token, bob.user.id, 'Second')

    const res = await app.inject({
      method: 'GET',
      url: `/api/conversations/${convId}/messages`,
      headers: { authorization: `Bearer ${alice.token}` },
    })
    expect(res.statusCode).toBe(200)
    const msgs = res.json()
    expect(msgs).toHaveLength(2)
    expect(msgs[0].body).toBe('Second')
    expect(msgs[1].body).toBe('First')
  })

  it('supports cursor-based pagination (before param)', async () => {
    const { alice, bob } = await setupFriends(app)
    const r1 = await sendMessage(app, alice.token, bob.user.id, 'First')
    const convId = r1.json().conversation_id
    const secondRes = await sendMessage(app, alice.token, bob.user.id, 'Second')
    const secondId = secondRes.json().id

    const res = await app.inject({
      method: 'GET',
      url: `/api/conversations/${convId}/messages?before=${secondId}`,
      headers: { authorization: `Bearer ${alice.token}` },
    })
    expect(res.statusCode).toBe(200)
    const msgs = res.json()
    expect(msgs).toHaveLength(1)
    expect(msgs[0].body).toBe('First')
  })

  it('supports forward pagination via after param (ASC order)', async () => {
    const { alice, bob } = await setupFriends(app)
    const r1 = await sendMessage(app, alice.token, bob.user.id, 'First')
    const convId = r1.json().conversation_id
    const firstId = r1.json().id
    await sendMessage(app, alice.token, bob.user.id, 'Second')
    await sendMessage(app, alice.token, bob.user.id, 'Third')

    const res = await app.inject({
      method: 'GET',
      url: `/api/conversations/${convId}/messages?after=${firstId}`,
      headers: { authorization: `Bearer ${alice.token}` },
    })
    expect(res.statusCode).toBe(200)
    const msgs = res.json()
    expect(msgs).toHaveLength(2)
    expect(msgs[0].body).toBe('Second') // ASC: older first
    expect(msgs[1].body).toBe('Third')
  })

  it('returns 400 when both before and after are provided', async () => {
    const { alice, bob } = await setupFriends(app)
    const r1 = await sendMessage(app, alice.token, bob.user.id, 'First')
    const convId = r1.json().conversation_id
    const id = r1.json().id

    const res = await app.inject({
      method: 'GET',
      url: `/api/conversations/${convId}/messages?before=${id}&after=${id}`,
      headers: { authorization: `Bearer ${alice.token}` },
    })
    expect(res.statusCode).toBe(400)
  })

  it('rejects malformed conversation id', async () => {
    const { alice } = await setupFriends(app)
    const res = await app.inject({
      method: 'GET',
      url: '/api/conversations/1abc/messages',
      headers: { authorization: `Bearer ${alice.token}` },
    })
    expect(res.statusCode).toBe(400)
  })

  it('paginates by message id', async () => {
    const { alice, bob } = await setupFriends(app)
    const r1 = await sendMessage(app, alice.token, bob.user.id, 'First')
    const convId = r1.json().conversation_id
    const r2 = await sendMessage(app, alice.token, bob.user.id, 'Second')
    const secondId = r2.json().id

    const res = await app.inject({
      method: 'GET',
      url: `/api/conversations/${convId}/messages?before=${secondId}`,
      headers: { authorization: `Bearer ${alice.token}` },
    })
    expect(res.statusCode).toBe(200)
    const msgs = res.json()
    expect(msgs).toHaveLength(1)
    expect(msgs[0].body).toBe('First')
  })

  it('returns 404 when user is not a member', async () => {
    const { alice, bob } = await setupFriends(app)
    const carol = await registerUser(app, { username: 'carol', email: 'carol@test.com', password: 'password123' })
    const msgRes = await sendMessage(app, alice.token, bob.user.id, 'Hi')
    const convId = msgRes.json().conversation_id

    const res = await app.inject({
      method: 'GET',
      url: `/api/conversations/${convId}/messages`,
      headers: { authorization: `Bearer ${carol.token}` },
    })
    expect(res.statusCode).toBe(404)
  })

  it('returns 401 when unauthenticated', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/conversations/1/messages' })
    expect(res.statusCode).toBe(401)
  })
})

// ─── PUT /api/conversations/:id/read ─────────────────────────────────────────

describe('PUT /api/conversations/:id/read', () => {
  let app: App

  beforeAll(async () => { app = await getApp() })
  afterAll(async () => { await app.close() })
  beforeEach(async () => { await truncateAll(app) })

  it('updates last_read_message_id and returns 200', async () => {
    const { alice, bob } = await setupFriends(app)
    const msgRes = await sendMessage(app, alice.token, bob.user.id, 'Hi')
    const convId = msgRes.json().conversation_id
    const firstMessageId = msgRes.json().id

    const res = await app.inject({
      method: 'PUT',
      url: `/api/conversations/${convId}/read`,
      headers: { authorization: `Bearer ${bob.token}` },
      payload: { last_read_message_id: firstMessageId },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().last_read_message_id).toBe(firstMessageId)
  })

  it('returns 404 when not a member', async () => {
    const { alice, bob } = await setupFriends(app)
    const carol = await registerUser(app, { username: 'carol', email: 'carol@test.com', password: 'password123' })
    const msgRes = await sendMessage(app, alice.token, bob.user.id, 'Hi')
    const convId = msgRes.json().conversation_id
    const firstMessageId = msgRes.json().id

    const res = await app.inject({
      method: 'PUT',
      url: `/api/conversations/${convId}/read`,
      headers: { authorization: `Bearer ${carol.token}` },
      payload: { last_read_message_id: firstMessageId },
    })
    expect(res.statusCode).toBe(404)
  })

  it('keeps the read cursor monotonic when an older ack arrives later', async () => {
    const { alice, bob } = await setupFriends(app)
    const first = await sendMessage(app, alice.token, bob.user.id, 'First')
    const convId = first.json().conversation_id
    const second = await sendMessage(app, alice.token, bob.user.id, 'Second')

    const newerRead = await app.inject({
      method: 'PUT',
      url: `/api/conversations/${convId}/read`,
      headers: { authorization: `Bearer ${bob.token}` },
      payload: { last_read_message_id: second.json().id },
    })
    expect(newerRead.statusCode).toBe(200)
    expect(newerRead.json().last_read_message_id).toBe(second.json().id)

    const olderRead = await app.inject({
      method: 'PUT',
      url: `/api/conversations/${convId}/read`,
      headers: { authorization: `Bearer ${bob.token}` },
      payload: { last_read_message_id: first.json().id },
    })
    expect(olderRead.statusCode).toBe(200)
    expect(olderRead.json().last_read_message_id).toBe(second.json().id)
  })

  it('returns 400 when last_read_message_id does not belong to the conversation', async () => {
    const { alice, bob } = await setupFriends(app)
    const first = await sendMessage(app, alice.token, bob.user.id, 'Hi')
    const convId = first.json().conversation_id

    const carol = await registerUser(app, { username: 'carol', email: 'carol@test.com', password: 'password123' })
    const dave = await registerUser(app, { username: 'dave', email: 'dave@test.com', password: 'password123' })
    const req = await sendFriendRequest(app, carol.token, dave.user.id)
    await acceptFriendRequest(app, dave.token, req.json().id)
    const otherConversationMessage = await sendMessage(app, carol.token, dave.user.id, 'Elsewhere')

    const res = await app.inject({
      method: 'PUT',
      url: `/api/conversations/${convId}/read`,
      headers: { authorization: `Bearer ${bob.token}` },
      payload: { last_read_message_id: otherConversationMessage.json().id },
    })
    expect(res.statusCode).toBe(400)
  })

  it('rejects malformed conversation id', async () => {
    const { alice } = await setupFriends(app)
    const res = await app.inject({
      method: 'PUT',
      url: '/api/conversations/1abc/read',
      headers: { authorization: `Bearer ${alice.token}` },
      payload: { last_read_message_id: 1 },
    })
    expect(res.statusCode).toBe(400)
  })

  it('rejects a missing last_read_message_id', async () => {
    const { alice, bob } = await setupFriends(app)
    const msgRes = await sendMessage(app, alice.token, bob.user.id, 'Hi')
    const convId = msgRes.json().conversation_id

    const res = await app.inject({
      method: 'PUT',
      url: `/api/conversations/${convId}/read`,
      headers: { authorization: `Bearer ${bob.token}` },
      payload: {},
    })
    expect(res.statusCode).toBe(400)
  })

  it('returns 401 when unauthenticated', async () => {
    const res = await app.inject({
      method: 'PUT',
      url: '/api/conversations/1/read',
      payload: { last_read_message_id: 1 },
    })
    expect(res.statusCode).toBe(401)
  })
})
