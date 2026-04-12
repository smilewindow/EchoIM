import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { mkdir, writeFile, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { getApp } from './helpers.js'
import type { App } from './helpers.js'

describe('Static file serving', () => {
  let app: App
  const uploadsDir = join(process.cwd(), 'uploads', 'avatars')
  const testFile = 'test-static.txt'
  const testFilePath = join(uploadsDir, testFile)

  beforeAll(async () => {
    await mkdir(uploadsDir, { recursive: true })
    await writeFile(testFilePath, 'hello static')
    app = await getApp()
  })

  afterAll(async () => {
    await app.close()
    await rm(testFilePath, { force: true })
  })

  it('serves files from /uploads/avatars/', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/uploads/avatars/${testFile}`,
    })
    expect(res.statusCode).toBe(200)
    expect(res.body).toBe('hello static')
  })

  it('returns 404 for non-existent files', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/uploads/avatars/does-not-exist.png',
    })
    expect(res.statusCode).toBe(404)
  })
})
