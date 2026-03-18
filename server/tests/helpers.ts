import { buildApp } from '../src/app.js'

export type App = Awaited<ReturnType<typeof buildApp>>

export async function getApp(): Promise<App> {
  return buildApp()
}

export async function truncateAll(app: App) {
  await app.pool.query(
    'TRUNCATE users, friend_requests, conversations, conversation_members, messages RESTART IDENTITY CASCADE',
  )
}

interface RegisterPayload {
  username?: string
  email?: string
  password?: string
}

export async function registerUser(app: App, overrides: RegisterPayload = {}) {
  const body = {
    username: 'alice',
    email: 'alice@test.com',
    password: 'password123',
    ...overrides,
  }
  const res = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: body,
  })
  return res.json() as { token: string; user: { id: number; username: string; email: string } }
}
