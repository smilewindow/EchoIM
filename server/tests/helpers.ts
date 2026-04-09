import WebSocket from 'ws'
import { buildApp } from '../src/app.js'

export type App = Awaited<ReturnType<typeof buildApp>>
export type UserInfo = { token: string; user: { id: number; username: string; email: string } }

export async function getApp(): Promise<App> {
  return buildApp()
}

export async function truncateAll(app: App) {
  await app.pool.query(
    'TRUNCATE users, friend_requests, conversations, conversation_members, messages RESTART IDENTITY CASCADE',
  )
}

export async function flushRedis(app: App) {
  await app.redis.pub.flushdb()
}

export function getInviteCode(): string {
  return process.env['INVITE_CODES']?.split(',').map((code) => code.trim()).find(Boolean) ?? 'letschat'
}

interface RegisterPayload {
  username?: string
  email?: string
  password?: string
  inviteCode?: string
}

export async function registerUser(app: App, overrides: RegisterPayload = {}) {
  const defaultInviteCode = getInviteCode()
  const body = {
    username: 'alice',
    email: 'alice@test.com',
    password: 'password123',
    inviteCode: defaultInviteCode,
    ...overrides,
  }
  const res = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: body,
  })
  return res.json() as UserInfo
}

export async function setupFriends(app: App): Promise<{ alice: UserInfo; bob: UserInfo }> {
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

export function connectWs(port: number, token: string, timeout = 5000): Promise<WebSocket> {
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
    }, timeout)

    ws.on('message', handleMessage)
    ws.once('unexpected-response', handleUnexpectedResponse)
    ws.once('error', handleError)
    ws.once('close', handleClose)
  })
}

export function waitForEvent(ws: WebSocket, type: string, timeout = 5000): Promise<unknown> {
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

export async function waitForCondition(
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
