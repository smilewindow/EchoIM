import type { FastifyPluginAsync } from 'fastify'
import { authenticate } from '../hooks/authenticate.js'

const userRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.addHook('preHandler', authenticate)

  fastify.get('/me', async (request, reply) => {
    const result = await fastify.pool.query(
      `SELECT id, username, email, display_name, avatar_url, created_at
       FROM users WHERE id = $1`,
      [request.user.id]
    )
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

    const result = await fastify.pool.query(
      `UPDATE users
       SET display_name = COALESCE($1, display_name),
           avatar_url   = COALESCE($2, avatar_url)
       WHERE id = $3
       RETURNING id, username, email, display_name, avatar_url, created_at`,
      [trimmedDisplayName ?? null, avatar_url ?? null, request.user.id]
    )

    return reply.status(200).send(result.rows[0])
  })
}

export default userRoutes
