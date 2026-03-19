import type { FastifyPluginAsync } from 'fastify'
import { authenticate } from '../hooks/authenticate.js'

const conversationRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.addHook('preHandler', authenticate)

  // GET /api/conversations
  fastify.get('/', async (request, reply) => {
    const userId = request.user.id

    const result = await fastify.pool.query(
      `SELECT c.id, c.created_at,
        (SELECT COUNT(*)::int FROM messages m WHERE m.conversation_id = c.id AND m.sender_id != $1 AND m.created_at > COALESCE(cm.last_read_at, '1970-01-01')) AS unread_count,
        last_msg.body AS last_message_body,
        last_msg.sender_id AS last_message_sender_id,
        last_msg.created_at AS last_message_at,
        peer.id AS peer_id, peer.username AS peer_username, peer.display_name AS peer_display_name, peer.avatar_url AS peer_avatar_url
       FROM conversation_members cm
       JOIN conversations c ON c.id = cm.conversation_id
       LEFT JOIN LATERAL (
         SELECT body, sender_id, created_at FROM messages WHERE conversation_id = c.id ORDER BY id DESC LIMIT 1
       ) last_msg ON true
       JOIN conversation_members cm2 ON cm2.conversation_id = c.id AND cm2.user_id != $1
       JOIN users peer ON peer.id = cm2.user_id
       WHERE cm.user_id = $1
       ORDER BY last_msg.created_at DESC NULLS LAST`,
      [userId]
    )

    return reply.status(200).send(result.rows)
  })

  // GET /api/conversations/:id/messages
  fastify.get('/:id/messages', {
    schema: {
      querystring: {
        type: 'object',
        properties: {
          before: { type: 'integer', minimum: 1 },
        },
        additionalProperties: false,
      },
    },
  }, async (request, reply) => {
    const { id } = request.params as { id: string }
    const { before } = request.query as { before?: number }
    const userId = request.user.id

    if (!/^\d+$/.test(id)) {
      return reply.status(400).send({ error: 'Invalid id' })
    }
    const convId = Number(id)

    // Verify membership
    const memberCheck = await fastify.pool.query(
      'SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
      [convId, userId]
    )
    if (memberCheck.rowCount === 0) {
      return reply.status(404).send({ error: 'Not a member of this conversation' })
    }

    let result
    if (before) {
      result = await fastify.pool.query(
        'SELECT * FROM messages WHERE conversation_id = $1 AND id < $2 ORDER BY id DESC LIMIT 50',
        [convId, before]
      )
    } else {
      result = await fastify.pool.query(
        'SELECT * FROM messages WHERE conversation_id = $1 ORDER BY id DESC LIMIT 50',
        [convId]
      )
    }

    return reply.status(200).send(result.rows)
  })

  // PUT /api/conversations/:id/read
  fastify.put('/:id/read', async (request, reply) => {
    const { id } = request.params as { id: string }
    const userId = request.user.id

    if (!/^\d+$/.test(id)) {
      return reply.status(400).send({ error: 'Invalid id' })
    }
    const convId = Number(id)

    const result = await fastify.pool.query(
      `UPDATE conversation_members SET last_read_at = NOW()
       WHERE conversation_id = $1 AND user_id = $2
       RETURNING last_read_at`,
      [convId, userId]
    )

    if (result.rowCount === 0) {
      return reply.status(404).send({ error: 'Not a member of this conversation' })
    }

    return reply.status(200).send({ last_read_at: result.rows[0].last_read_at })
  })
}

export default conversationRoutes
