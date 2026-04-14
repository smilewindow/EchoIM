import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest'
import sharp from 'sharp'
import { rm, readdir, readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { getApp, truncateAll, registerUser } from './helpers.js'
import type { App } from './helpers.js'

describe('POST /api/upload/avatar', () => {
  let app: App
  let token: string
  let userId: number
  const uploadsDir = join(process.cwd(), 'uploads', 'avatars')

  beforeAll(async () => {
    app = await getApp()
  })

  afterAll(async () => {
    await app.close()
  })

  beforeEach(async () => {
    await truncateAll(app)
    const result = await registerUser(app)
    token = result.token
    userId = result.user.id
    // Clean up test uploads
    const files = await readdir(uploadsDir).catch(() => [])
    for (const file of files) {
      if (file !== '.gitkeep') {
        await rm(join(uploadsDir, file), { force: true })
      }
    }
  })

  it('returns 401 when unauthenticated', async () => {
    const form = createMultipartForm('avatar', Buffer.from('fake'), 'test.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: form.headers,
      payload: form.body,
    })
    expect(res.statusCode).toBe(401)
  })

  it('returns 400 when no file provided (empty multipart)', async () => {
    const form = createEmptyMultipartForm()
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: {
        authorization: `Bearer ${token}`,
        ...form.headers,
      },
      payload: form.body,
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('No file provided')
  })

  it('returns 400 for invalid image (not decodable by sharp)', async () => {
    const form = createMultipartForm('avatar', Buffer.from('not an image'), 'test.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: {
        authorization: `Bearer ${token}`,
        ...form.headers,
      },
      payload: form.body,
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toContain('Invalid image')
  })

  it('returns 200 and updates user avatar_url for valid PNG', async () => {
    // Minimal valid PNG (1x1 transparent)
    const pngBuffer = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
      0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ])
    const form = createMultipartForm('avatar', pngBuffer, 'avatar.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: {
        authorization: `Bearer ${token}`,
        ...form.headers,
      },
      payload: form.body,
    })
    expect(res.statusCode).toBe(200)
    const data = res.json<{ avatar_url: string }>()
    expect(data.avatar_url).toMatch(/^\/uploads\/avatars\/\d+-\d+\.jpg$/)

    // Verify user record was updated
    const userRes = await app.inject({
      method: 'GET',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${token}` },
    })
    expect(userRes.json().avatar_url).toBe(data.avatar_url)
  })

  it('returns 401 when token is valid but user no longer exists', async () => {
    // Delete user after getting token
    await app.pool.query('DELETE FROM users WHERE id = $1', [userId])

    const pngBuffer = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
      0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ])
    const form = createMultipartForm('avatar', pngBuffer, 'avatar.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: {
        authorization: `Bearer ${token}`,
        ...form.headers,
      },
      payload: form.body,
    })
    expect(res.statusCode).toBe(401)
    expect(res.json().error).toBe('User no longer exists')

    // Verify no orphan file was left
    const files = await readdir(uploadsDir)
    const avatarFiles = files.filter((f) => f.startsWith(`${userId}-`))
    expect(avatarFiles).toHaveLength(0)
  })

  it('deletes old avatar file when uploading new one', async () => {
    // Upload first avatar
    const png1 = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
      0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ])
    const form1 = createMultipartForm('avatar', png1, 'avatar1.png', 'image/png')
    const res1 = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: { authorization: `Bearer ${token}`, ...form1.headers },
      payload: form1.body,
    })
    const oldUrl = res1.json<{ avatar_url: string }>().avatar_url
    const oldFilename = oldUrl.split('/').pop()!

    // Upload second avatar
    const form2 = createMultipartForm('avatar', png1, 'avatar2.png', 'image/png')
    const res2 = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: { authorization: `Bearer ${token}`, ...form2.headers },
      payload: form2.body,
    })
    expect(res2.statusCode).toBe(200)

    // Old file should be deleted
    const files = await readdir(uploadsDir)
    expect(files).not.toContain(oldFilename)
  })

  it('processes image to JPEG format', async () => {
    const pngBuffer = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
      0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ])
    const form = createMultipartForm('avatar', pngBuffer, 'avatar.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: { authorization: `Bearer ${token}`, ...form.headers },
      payload: form.body,
    })
    const url = res.json<{ avatar_url: string }>().avatar_url
    const filename = url.split('/').pop()!
    const filepath = join(uploadsDir, filename)

    // File should be JPEG (magic bytes: FF D8)
    const fileBuffer = await readFile(filepath)
    expect(fileBuffer[0]).toBe(0xff)
    expect(fileBuffer[1]).toBe(0xd8)
  })

  it('flattens transparent PNG to white background instead of black', async () => {
    // Same 1x1 transparent PNG used in other tests
    const pngBuffer = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
      0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ])
    const form = createMultipartForm('avatar', pngBuffer, 'transparent.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: { authorization: `Bearer ${token}`, ...form.headers },
      payload: form.body,
    })
    expect(res.statusCode).toBe(200)
    const url = res.json<{ avatar_url: string }>().avatar_url
    const filename = url.split('/').pop()!
    const filepath = join(uploadsDir, filename)

    // Read the output JPEG with sharp and check the top-left pixel is white, not black
    const { data } = await sharp(await readFile(filepath))
      .raw()
      .toBuffer({ resolveWithObject: true })
    // First 3 bytes = R, G, B of pixel (0,0)
    expect(data[0]).toBeGreaterThan(250) // R ≈ 255
    expect(data[1]).toBeGreaterThan(250) // G ≈ 255
    expect(data[2]).toBeGreaterThan(250) // B ≈ 255
  })
})

describe('POST /api/upload/message-image', () => {
  let app: App
  let token: string
  let userId: number
  const messagesUploadsDir = join(process.cwd(), 'uploads', 'messages')

  beforeAll(async () => {
    app = await getApp()
  })

  afterAll(async () => {
    await app.close()
  })

  beforeEach(async () => {
    await truncateAll(app)
    const result = await registerUser(app)
    token = result.token
    userId = result.user.id
    // Clean up test uploads
    const files = await readdir(messagesUploadsDir).catch(() => [])
    for (const file of files) {
      if (file !== '.gitkeep') {
        await rm(join(messagesUploadsDir, file), { force: true })
      }
    }
  })

  it('returns 401 when unauthenticated', async () => {
    const form = createMultipartForm('file', Buffer.from('fake'), 'test.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/message-image',
      headers: form.headers,
      payload: form.body,
    })
    expect(res.statusCode).toBe(401)
  })

  it('returns 400 when no file provided (empty multipart)', async () => {
    const form = createEmptyMultipartForm()
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/message-image',
      headers: {
        authorization: `Bearer ${token}`,
        ...form.headers,
      },
      payload: form.body,
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('No file provided')
  })

  it('returns 400 for invalid image (not decodable by sharp)', async () => {
    const form = createMultipartForm('file', Buffer.from('not an image'), 'test.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/message-image',
      headers: {
        authorization: `Bearer ${token}`,
        ...form.headers,
      },
      payload: form.body,
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toContain('Invalid image')
  })

  it('returns 200 with media_url matching expected pattern for valid PNG', async () => {
    const pngBuffer = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
      0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ])
    const form = createMultipartForm('file', pngBuffer, 'image.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/message-image',
      headers: {
        authorization: `Bearer ${token}`,
        ...form.headers,
      },
      payload: form.body,
    })
    expect(res.statusCode).toBe(200)
    const data = res.json<{ media_url: string }>()
    expect(data.media_url).toMatch(new RegExp(`^/uploads/messages/${userId}-\\d{10,16}\\.jpg$`))
  })

  it('saves file to disk on successful upload', async () => {
    const pngBuffer = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
      0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ])
    const form = createMultipartForm('file', pngBuffer, 'image.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/message-image',
      headers: {
        authorization: `Bearer ${token}`,
        ...form.headers,
      },
      payload: form.body,
    })
    expect(res.statusCode).toBe(200)
    const { media_url } = res.json<{ media_url: string }>()
    const filename = media_url.split('/').pop()!
    const filepath = join(messagesUploadsDir, filename)

    // File should be JPEG (magic bytes: FF D8)
    const fileBuffer = await readFile(filepath)
    expect(fileBuffer[0]).toBe(0xff)
    expect(fileBuffer[1]).toBe(0xd8)
  })
})

function createMultipartForm(
  fieldName: string,
  fileContent: Buffer,
  fileName: string,
  contentType: string,
) {
  const boundary = '----FormBoundary' + Math.random().toString(36).substring(2)
  const body = Buffer.concat([
    Buffer.from(`--${boundary}\r\n`),
    Buffer.from(`Content-Disposition: form-data; name="${fieldName}"; filename="${fileName}"\r\n`),
    Buffer.from(`Content-Type: ${contentType}\r\n\r\n`),
    fileContent,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ])
  return {
    headers: { 'content-type': `multipart/form-data; boundary=${boundary}` },
    body,
  }
}

function createEmptyMultipartForm() {
  const boundary = '----FormBoundary' + Math.random().toString(36).substring(2)
  const body = Buffer.from(`--${boundary}--\r\n`)
  return {
    headers: { 'content-type': `multipart/form-data; boundary=${boundary}` },
    body,
  }
}
