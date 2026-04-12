import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest'
import { mkdir, writeFile, readdir } from 'node:fs/promises'
import { join } from 'node:path'
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

  it('returns 401 when token is valid but the user no longer exists', async () => {
    await app.pool.query('DELETE FROM users')

    const res = await app.inject({
      method: 'GET',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(res.statusCode).toBe(401)
    expect(res.json().error).toBe('User no longer exists')
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

  it('returns 200 and allows clearing existing profile fields with empty strings', async () => {
    await app.inject({
      method: 'PUT',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${token}` },
      payload: {
        display_name: 'Alice W',
        avatar_url: 'https://example.com/alice.png',
      },
    })

    const res = await app.inject({
      method: 'PUT',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${token}` },
      payload: {
        display_name: '',
        avatar_url: '',
      },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json().display_name).toBe('')
    expect(res.json().avatar_url).toBe('')

    const dbUser = await app.pool.query(
      'SELECT display_name, avatar_url FROM users WHERE username = $1',
      ['alice'],
    )
    expect(dbUser.rows[0]?.display_name).toBe('')
    expect(dbUser.rows[0]?.avatar_url).toBe('')
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

  it('returns 401 when token is valid but the user no longer exists', async () => {
    await app.pool.query('DELETE FROM users')

    const res = await app.inject({
      method: 'PUT',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${token}` },
      payload: { display_name: 'Alice W' },
    })

    expect(res.statusCode).toBe(401)
    expect(res.json().error).toBe('User no longer exists')
  })

  it('deletes old local avatar file when avatar_url changes to external URL', async () => {
    const uploadsDir = join(process.cwd(), 'uploads', 'avatars')
    await mkdir(uploadsDir, { recursive: true })

    // Simulate an existing local avatar
    const oldFilename = `${1}-${Date.now()}.jpg`
    const oldFilepath = join(uploadsDir, oldFilename)
    const oldAvatarUrl = `/uploads/avatars/${oldFilename}`
    await writeFile(oldFilepath, Buffer.from('fake image'))

    // Set user's avatar to local file
    await app.pool.query('UPDATE users SET avatar_url = $1 WHERE username = $2', [
      oldAvatarUrl,
      'alice',
    ])

    // Update to external URL
    const res = await app.inject({
      method: 'PUT',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${token}` },
      payload: { avatar_url: 'https://example.com/new-avatar.png' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json().avatar_url).toBe('https://example.com/new-avatar.png')

    // Old local file should be deleted
    const files = await readdir(uploadsDir).catch(() => [])
    expect(files).not.toContain(oldFilename)
  })

  it('deletes old local avatar file when avatar_url is cleared', async () => {
    const uploadsDir = join(process.cwd(), 'uploads', 'avatars')
    await mkdir(uploadsDir, { recursive: true })

    // Simulate an existing local avatar
    const oldFilename = `${1}-${Date.now()}.jpg`
    const oldFilepath = join(uploadsDir, oldFilename)
    const oldAvatarUrl = `/uploads/avatars/${oldFilename}`
    await writeFile(oldFilepath, Buffer.from('fake image'))

    // Set user's avatar to local file
    await app.pool.query('UPDATE users SET avatar_url = $1 WHERE username = $2', [
      oldAvatarUrl,
      'alice',
    ])

    // Clear avatar
    const res = await app.inject({
      method: 'PUT',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${token}` },
      payload: { avatar_url: '' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json().avatar_url).toBe('')

    // Old local file should be deleted
    const files = await readdir(uploadsDir).catch(() => [])
    expect(files).not.toContain(oldFilename)
  })
})
