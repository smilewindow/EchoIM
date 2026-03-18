import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest'
import { getApp, truncateAll, registerUser } from './helpers.js'
import type { App } from './helpers.js'

describe('GET /api/users/me', () => {
  let app: App
  let token: string

  beforeAll(async () => { app = await getApp() })
  afterAll(async () => { await app.close() })
  beforeEach(async () => {
    await truncateAll(app)
    const result = await registerUser(app)
    token = result.token
  })

  it('returns 200 with user profile when authenticated', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${token}` },
    })
    expect(res.statusCode).toBe(200)
    const user = res.json()
    expect(user.username).toBe('alice')
    expect(user.email).toBe('alice@test.com')
    expect(user).toHaveProperty('created_at')
    expect(user).not.toHaveProperty('password_hash')
  })

  it('returns 401 when no Authorization header', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/users/me' })
    expect(res.statusCode).toBe(401)
  })

  it('returns 401 when token is invalid', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/users/me',
      headers: { authorization: 'Bearer invalidtoken' },
    })
    expect(res.statusCode).toBe(401)
  })
})

describe('PUT /api/users/me', () => {
  let app: App
  let token: string

  beforeAll(async () => { app = await getApp() })
  afterAll(async () => { await app.close() })
  beforeEach(async () => {
    await truncateAll(app)
    const result = await registerUser(app)
    token = result.token
  })

  it('returns 200 with updated display_name', async () => {
    const res = await app.inject({
      method: 'PUT',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${token}` },
      payload: { display_name: 'Alice W' },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().display_name).toBe('Alice W')
  })

  it('returns 200 with updated avatar_url', async () => {
    const res = await app.inject({
      method: 'PUT',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${token}` },
      payload: { avatar_url: 'https://example.com/alice.png' },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().avatar_url).toBe('https://example.com/alice.png')
  })

  it('returns 400 when body has no fields to update', async () => {
    const res = await app.inject({
      method: 'PUT',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${token}` },
      payload: {},
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('No fields to update')
  })

  it('returns 401 when unauthenticated', async () => {
    const res = await app.inject({
      method: 'PUT',
      url: '/api/users/me',
      payload: { display_name: 'Alice W' },
    })
    expect(res.statusCode).toBe(401)
  })
})
