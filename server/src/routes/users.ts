import type { FastifyPluginAsync } from 'fastify'
import { rm } from 'node:fs/promises'
import { join } from 'node:path'
import { authenticate } from '../hooks/authenticate.js'

const UPLOADS_DIR = join(process.cwd(), 'uploads', 'avatars')

const userRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.addHook('preHandler', authenticate)

  fastify.get('/me', async (request, reply) => {
    const result = await fastify.pool.query(
      `SELECT id, username, email, display_name, avatar_url, created_at
       FROM users WHERE id = $1`,
      [request.user.id]
    )
    if (result.rowCount === 0) {
      // JWT 仍然合法但用户已被删库/清库时，明确返回 401，避免前端拿到 200 空响应体。
      return reply.status(401).send({ error: 'User no longer exists' })
    }
    return reply.status(200).send(result.rows[0])
  })

  fastify.put('/me', {
    schema: {
      body: {
        type: 'object',
        additionalProperties: false,
        properties: {
          display_name: { type: 'string', maxLength: 100 },
          avatar_url: { type: 'string', maxLength: 2048 },
        },
      },
    },
  }, async (request, reply) => {
    const { display_name, avatar_url } = request.body as {
      display_name?: string
      avatar_url?: string
    }

    if (display_name === undefined && avatar_url === undefined) {
      return reply.status(400).send({ error: 'No fields to update' })
    }

    const trimmedDisplayName = display_name !== undefined ? display_name.trim() : undefined

    // Get old avatar URL before update (for cleanup)
    let oldAvatarUrl: string | null = null
    if (avatar_url !== undefined) {
      const oldResult = await fastify.pool.query(
        'SELECT avatar_url FROM users WHERE id = $1',
        [request.user.id],
      )
      if (oldResult.rowCount === 0) {
        return reply.status(401).send({ error: 'User no longer exists' })
      }
      oldAvatarUrl = oldResult.rows[0]?.avatar_url as string | null
    }

    const result = await fastify.pool.query(
      `UPDATE users
       SET display_name = COALESCE($1, display_name),
           avatar_url   = COALESCE($2, avatar_url)
       WHERE id = $3
       RETURNING id, username, email, display_name, avatar_url, created_at`,
      [trimmedDisplayName ?? null, avatar_url ?? null, request.user.id]
    )
    if (result.rowCount === 0) {
      return reply.status(401).send({ error: 'User no longer exists' })
    }

    // Clean up old local avatar file if avatar_url changed (best-effort)
    if (
      avatar_url !== undefined &&
      oldAvatarUrl?.startsWith('/uploads/avatars/') &&
      oldAvatarUrl !== avatar_url
    ) {
      const oldFilename = oldAvatarUrl.split('/').pop()
      if (oldFilename) {
        await rm(join(UPLOADS_DIR, oldFilename), { force: true }).catch((err) => {
          fastify.log.warn({ err, oldFilename }, 'failed to cleanup old avatar file')
        })
      }
    }

    return reply.status(200).send(result.rows[0])
  })

  fastify.get('/search', {
    schema: {
      querystring: {
        type: 'object',
        additionalProperties: false,
        required: ['q'],
        properties: {
          q: { type: 'string', minLength: 1, maxLength: 50 },
        },
      },
    },
  }, async (request, reply) => {
    const { q } = request.query as { q: string }
    const escaped = q.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_')
    const result = await fastify.pool.query(
      `SELECT id, username, display_name, avatar_url
       FROM users
       WHERE username ILIKE '%' || $1 || '%' ESCAPE '\\' AND id <> $2
       LIMIT 20`,
      [escaped, request.user.id]
    )
    return reply.status(200).send(result.rows)
  })
}

export default userRoutes
