import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest'
import { join } from 'node:path'
import { mkdir, readFile, readdir, rm } from 'node:fs/promises'
import { getApp, registerUser, truncateAll } from './helpers.js'
import type { App } from './helpers.js'

describe('Configurable uploads directory', () => {
  let app: App
  let token: string
  let previousUploadsDir: string | undefined

  const uploadsRoot = join(process.cwd(), 'test-uploads')
  const avatarsDir = join(uploadsRoot, 'avatars')

  beforeAll(async () => {
    previousUploadsDir = process.env['UPLOADS_DIR']
    process.env['UPLOADS_DIR'] = uploadsRoot
    await mkdir(avatarsDir, { recursive: true })
    app = await getApp()
  })

  afterAll(async () => {
    await app.close()
    if (previousUploadsDir === undefined) {
      delete process.env['UPLOADS_DIR']
    } else {
      process.env['UPLOADS_DIR'] = previousUploadsDir
    }
    await rm(uploadsRoot, { recursive: true, force: true })
  })

  beforeEach(async () => {
    await truncateAll(app)
    const result = await registerUser(app)
    token = result.token

    const files = await readdir(avatarsDir).catch(() => [])
    for (const file of files) {
      await rm(join(avatarsDir, file), { force: true })
    }
  })

  it('writes uploads into UPLOADS_DIR and serves them statically', async () => {
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

    const boundary = '----echoim-upload-test-boundary'
    const formBody = Buffer.concat([
      Buffer.from(`--${boundary}\r\n`),
      Buffer.from('Content-Disposition: form-data; name="avatar"; filename="avatar.png"\r\n'),
      Buffer.from('Content-Type: image/png\r\n\r\n'),
      pngBuffer,
      Buffer.from(`\r\n--${boundary}--\r\n`),
    ])

    const uploadRes = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': `multipart/form-data; boundary=${boundary}`,
      },
      payload: formBody,
    })

    expect(uploadRes.statusCode).toBe(200)
    const avatarUrl = uploadRes.json<{ avatar_url: string }>().avatar_url
    const filename = avatarUrl.split('/').pop()
    expect(filename).toBeTruthy()

    const savedFile = await readFile(join(avatarsDir, filename!))
    expect(savedFile[0]).toBe(0xff)
    expect(savedFile[1]).toBe(0xd8)

    const staticRes = await app.inject({
      method: 'GET',
      url: avatarUrl,
    })

    expect(staticRes.statusCode).toBe(200)
    expect(staticRes.body.length).toBeGreaterThan(0)
  })
})
