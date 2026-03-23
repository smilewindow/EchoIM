import type { Page } from '@playwright/test'
import { E2E_DATABASE_URL, E2E_SERVER_ORIGIN } from './config.js'

const API = `${E2E_SERVER_ORIGIN}/api`

export interface SeedUser {
  id: number
  username: string
  email: string
  token: string
}

export interface SentMessage {
  id: number
  conversation_id: number
  sender_id: number
  body: string
  created_at: string
}

export async function seedUser(
  username: string,
  email: string,
  password: string,
): Promise<SeedUser> {
  const res = await fetch(`${API}/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, email, password }),
  })
  if (!res.ok) {
    const body = await res.text()
    throw new Error(`seedUser failed (${res.status}): ${body}`)
  }
  const data = await res.json()
  return { id: data.user.id, username: data.user.username, email, token: data.token }
}

export async function loginAs(page: Page, email: string, password: string) {
  await page.goto('/login')
  await page.locator('#email').fill(email)
  await page.locator('#password').fill(password)
  await page.getByRole('button', { name: 'Sign in' }).click()
  await page.waitForURL('/')
}

/** User A sends a friend request to B; B accepts it. */
export async function makeFriends(tokenA: string, tokenB: string, userBId: number) {
  // A sends request to B
  const sendRes = await fetch(`${API}/friend-requests`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${tokenA}`,
    },
    body: JSON.stringify({ recipient_id: userBId }),
  })
  if (!sendRes.ok) {
    const body = await sendRes.text()
    throw new Error(`makeFriends send failed (${sendRes.status}): ${body}`)
  }
  const request = await sendRes.json()

  // B accepts the request
  const acceptRes = await fetch(`${API}/friend-requests/${request.id}`, {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${tokenB}`,
    },
    body: JSON.stringify({ status: 'accepted' }),
  })
  if (!acceptRes.ok) {
    const body = await acceptRes.text()
    throw new Error(`makeFriends accept failed (${acceptRes.status}): ${body}`)
  }
}

/** Send a message via REST API (simulates a user sending without a browser). */
export async function sendMessageApi(
  token: string,
  recipientId: number,
  body: string,
): Promise<SentMessage> {
  const res = await fetch(`${API}/messages`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ recipient_id: recipientId, body }),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`sendMessageApi failed (${res.status}): ${text}`)
  }

  return res.json()
}

/** Mark a conversation as read via REST API. */
export async function markConversationRead(token: string, conversationId: number): Promise<void> {
  const res = await fetch(`${API}/conversations/${conversationId}/read`, {
    method: 'PUT',
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`markConversationRead failed (${res.status}): ${text}`)
  }
}

/** Truncate all tables so each test starts from a clean slate. */
export async function cleanDatabase() {
  const { Client } = await import('pg')
  const client = new Client({
    connectionString: E2E_DATABASE_URL,
  })
  await client.connect()
  await client.query(
    'TRUNCATE messages, conversation_members, conversations, friend_requests, users RESTART IDENTITY CASCADE',
  )
  await client.end()
}
