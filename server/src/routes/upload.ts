import type { FastifyPluginAsync } from 'fastify'
import fastifyMultipart from '@fastify/multipart'
import sharp from 'sharp'
import { mkdir, writeFile, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { authenticate } from '../hooks/authenticate.js'

const MAX_FILE_SIZE = 10 * 1024 * 1024 // 10MB (front-end compresses before upload)

const AVATAR_CONFIG = {
  outputSize: 400,
  outputQuality: 80,
  uploadsDir: join(process.cwd(), 'uploads', 'avatars'),
  urlPrefix: '/uploads/avatars',
}

const MESSAGE_IMAGE_CONFIG = {
  maxDimension: 1600,
  outputQuality: 80,
  uploadsDir: join(process.cwd(), 'uploads', 'messages'),
  urlPrefix: '/uploads/messages',
}

const uploadRoutes: FastifyPluginAsync = async (fastify) => {
  await fastify.register(fastifyMultipart, {
    limits: { fileSize: MAX_FILE_SIZE },
  })

  fastify.addHook('preHandler', authenticate)

  fastify.post('/avatar', async (request, reply) => {
    const file = await request.file()

    if (!file) {
      return reply.status(400).send({ error: 'No file provided' })
    }

    const buffer = await file.toBuffer()

    // Validate and process with sharp (validates magic bytes implicitly)
    let processedBuffer: Buffer
    try {
      processedBuffer = await sharp(buffer)
        .flatten({ background: { r: 255, g: 255, b: 255 } })
        .resize(AVATAR_CONFIG.outputSize, AVATAR_CONFIG.outputSize, {
          fit: 'cover',
          position: 'center',
        })
        .jpeg({ quality: AVATAR_CONFIG.outputQuality })
        .toBuffer()
    } catch {
      return reply.status(400).send({ error: 'Invalid image file' })
    }

    // Generate filename
    const filename = `${request.user.id}-${Date.now()}.jpg`
    const filepath = join(AVATAR_CONFIG.uploadsDir, filename)
    const avatarUrl = `${AVATAR_CONFIG.urlPrefix}/${filename}`

    // Ensure directory exists
    await mkdir(AVATAR_CONFIG.uploadsDir, { recursive: true })

    // Get old avatar URL before update
    const oldAvatarResult = await fastify.pool.query(
      'SELECT avatar_url FROM users WHERE id = $1',
      [request.user.id],
    )

    // User might have been deleted while processing
    if (oldAvatarResult.rowCount === 0) {
      return reply.status(401).send({ error: 'User no longer exists' })
    }

    const oldAvatarUrl = oldAvatarResult.rows[0]?.avatar_url as string | null

    // Save file and update DB - clean up file on any failure
    try {
      await writeFile(filepath, processedBuffer)

      const updateResult = await fastify.pool.query(
        'UPDATE users SET avatar_url = $1 WHERE id = $2',
        [avatarUrl, request.user.id],
      )

      // User deleted between SELECT and UPDATE
      if (updateResult.rowCount === 0) {
        await rm(filepath, { force: true }).catch(() => {})
        return reply.status(401).send({ error: 'User no longer exists' })
      }
    } catch (err) {
      // Clean up file on DB error, then re-throw
      await rm(filepath, { force: true }).catch(() => {})
      throw err
    }

    // Delete old avatar file if it was a local upload (best-effort, don't fail the request)
    if (oldAvatarUrl?.startsWith(AVATAR_CONFIG.urlPrefix + '/')) {
      const oldFilename = oldAvatarUrl.split('/').pop()
      if (oldFilename && oldFilename !== filename) {
        await rm(join(AVATAR_CONFIG.uploadsDir, oldFilename), { force: true }).catch((err) => {
          fastify.log.warn({ err, oldFilename }, 'failed to cleanup old avatar file')
        })
      }
    }

    return reply.status(200).send({ avatar_url: avatarUrl })
  })

  fastify.post('/message-image', async (request, reply) => {
    const file = await request.file()

    if (!file) {
      return reply.status(400).send({ error: 'No file provided' })
    }

    const buffer = await file.toBuffer()

    // Validate and process with sharp (validates magic bytes implicitly)
    let processedBuffer: Buffer
    try {
      processedBuffer = await sharp(buffer)
        .flatten({ background: { r: 255, g: 255, b: 255 } })
        .resize(MESSAGE_IMAGE_CONFIG.maxDimension, MESSAGE_IMAGE_CONFIG.maxDimension, {
          fit: 'inside',
          withoutEnlargement: true,
        })
        .jpeg({ quality: MESSAGE_IMAGE_CONFIG.outputQuality })
        .toBuffer()
    } catch {
      return reply.status(400).send({ error: 'Invalid image file' })
    }

    // Generate filename
    const filename = `${request.user.id}-${Date.now()}.jpg`
    const filepath = join(MESSAGE_IMAGE_CONFIG.uploadsDir, filename)
    const mediaUrl = `${MESSAGE_IMAGE_CONFIG.urlPrefix}/${filename}`

    // Ensure directory exists
    await mkdir(MESSAGE_IMAGE_CONFIG.uploadsDir, { recursive: true })

    // Save file
    await writeFile(filepath, processedBuffer)

    return reply.status(200).send({ media_url: mediaUrl })
  })
}

export default uploadRoutes
