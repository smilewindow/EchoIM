import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest'
import jwt from 'jsonwebtoken'
import { getApp, truncateAll, registerUser, getInviteCode } from './helpers.js'
import type { App } from './helpers.js'

describe('POST /api/auth/register', () => {
  let app: App

  beforeAll(async () => { app = await getApp() })
  afterAll(async () => { await app.close() })
  beforeEach(async () => { await truncateAll(app) })

  it('returns 201 with token and user on valid input', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { username: 'alice', email: 'alice@test.com', password: 'password123', inviteCode: getInviteCode() },
    })
    expect(res.statusCode).toBe(201)
    const body = res.json()
    expect(body.token).toBeTruthy()
    expect(body.user.id).toBeTypeOf('number')
    expect(body.user.username).toBe('alice')
    expect(body.user.email).toBe('alice@test.com')
  })

  it('does not include password_hash in the response', async () => {
    const { user } = await registerUser(app)
    expect(user).not.toHaveProperty('password_hash')
  })

  it('returns a JWT containing the user id', async () => {
    const { token, user } = await registerUser(app)
    const decoded = jwt.verify(token, process.env['JWT_SECRET']!) as { id: number }
    expect(decoded.id).toBe(user.id)
  })

  it('returns 400 when username is missing', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { email: 'alice@test.com', password: 'password123' },
    })
    expect(res.statusCode).toBe(400)
  })

  it('returns 400 when password is shorter than 8 characters', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { username: 'alice', email: 'alice@test.com', password: 'short' },
    })
    expect(res.statusCode).toBe(400)
  })

  it('returns 400 when username is blank after trimming', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { username: '   ', email: 'alice@test.com', password: 'password123' },
    })
    expect(res.statusCode).toBe(400)
  })

  it('returns 400 when username is too short after trimming', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { username: ' a ', email: 'alice@test.com', password: 'password123' },
    })
    expect(res.statusCode).toBe(400)
  })

  it('returns 409 when email is already registered', async () => {
    await registerUser(app)
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { username: 'bob', email: 'alice@test.com', password: 'password123', inviteCode: getInviteCode() },
    })
    expect(res.statusCode).toBe(409)
    expect(res.json().error).toMatch(/email/i)
  })

  it('returns 409 when username is already taken', async () => {
    await registerUser(app)
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { username: 'alice', email: 'other@test.com', password: 'password123', inviteCode: getInviteCode() },
    })
    expect(res.statusCode).toBe(409)
    expect(res.json().error).toMatch(/username/i)
  })

  it('normalises email to lowercase and strips whitespace', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { username: 'alice', email: ' Alice@Test.COM ', password: 'password123', inviteCode: getInviteCode() },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json().user.email).toBe('alice@test.com')
  })
})

describe('POST /api/auth/login', () => {
  let app: App

  beforeAll(async () => { app = await getApp() })
  afterAll(async () => { await app.close() })
  beforeEach(async () => {
    await truncateAll(app)
    await registerUser(app)
  })

  it('returns 200 with token and user on valid credentials', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { email: 'alice@test.com', password: 'password123' },
    })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.token).toBeTruthy()
    expect(body.user.email).toBe('alice@test.com')
    expect(body.user).not.toHaveProperty('password_hash')
  })

  it('returns 401 on wrong password', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { email: 'alice@test.com', password: 'wrongpassword' },
    })
    expect(res.statusCode).toBe(401)
    expect(res.json().error).toBe('Invalid email or password')
  })

  it('returns 401 on non-existent email', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { email: 'nobody@test.com', password: 'password123' },
    })
    expect(res.statusCode).toBe(401)
    expect(res.json().error).toBe('Invalid email or password')
  })

  it('email lookup is case-insensitive', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { email: ' ALICE@TEST.COM ', password: 'password123' },
    })
    expect(res.statusCode).toBe(200)
  })

  it('returns 400 when extra fields are sent', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { email: 'alice@test.com', password: 'password123', extra: 'field' },
    })
    expect(res.statusCode).toBe(400)
  })
})
