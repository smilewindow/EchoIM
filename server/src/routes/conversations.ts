import type { FastifyPluginAsync } from 'fastify'
import { authenticate } from '../hooks/authenticate.js'

const conversationRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.addHook('preHandler', authenticate)

  // GET /api/conversations
  fastify.get('/', async (request, reply) => {
    const userId = request.user.id

    const result = await fastify.pool.query(
      `SELECT c.id, c.created_at,
        cm.last_read_message_id,
        (SELECT COUNT(*)::int FROM messages m WHERE m.conversation_id = c.id AND m.sender_id != $1 AND m.id > COALESCE(cm.last_read_message_id, 0)) AS unread_count,
        last_msg.body AS last_message_body,
        last_msg.sender_id AS last_message_sender_id,
        last_msg.created_at AS last_message_at,
        last_msg.message_type AS last_message_type,
        peer.id AS peer_id, peer.username AS peer_username, peer.display_name AS peer_display_name, peer.avatar_url AS peer_avatar_url
       FROM conversation_members cm
       JOIN conversations c ON c.id = cm.conversation_id
       LEFT JOIN LATERAL (
         SELECT body, sender_id, created_at, message_type FROM messages WHERE conversation_id = c.id ORDER BY id DESC LIMIT 1
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
          after: { type: 'integer', minimum: 1 },
        },
        additionalProperties: false,
      },
    },
  }, async (request, reply) => {
    const { id } = request.params as { id: string }
    const { before, after } = request.query as { before?: number; after?: number }
    const userId = request.user.id

    if (!/^\d+$/.test(id)) {
      return reply.status(400).send({ error: 'Invalid id' })
    }
    if (before !== undefined && after !== undefined) {
      return reply.status(400).send({ error: 'Cannot use both before and after' })
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
    } else if (after) {
      result = await fastify.pool.query(
        'SELECT * FROM messages WHERE conversation_id = $1 AND id > $2 ORDER BY id ASC LIMIT 50',
        [convId, after]
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
  fastify.put('/:id/read', {
    schema: {
      body: {
        type: 'object',
        required: ['last_read_message_id'],
        additionalProperties: false,
        properties: {
          last_read_message_id: { type: 'integer', minimum: 1 },
        },
      },
    },
  }, async (request, reply) => {
    const { id } = request.params as { id: string }
    const { last_read_message_id } = request.body as { last_read_message_id: number }
    const userId = request.user.id

    if (!/^\d+$/.test(id)) {
      return reply.status(400).send({ error: 'Invalid id' })
    }
    const convId = Number(id)

    const checkResult = await fastify.pool.query(
      `SELECT
        EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2) AS is_member,
        EXISTS(SELECT 1 FROM messages WHERE id = $3 AND conversation_id = $1) AS is_valid_message`,
      [convId, userId, last_read_message_id]
    )
    const { is_member, is_valid_message } = checkResult.rows[0]
    if (!is_member) {
      return reply.status(404).send({ error: 'Not a member of this conversation' })
    }
    if (!is_valid_message) {
      return reply.status(400).send({ error: 'Invalid last_read_message_id' })
    }

    const result = await fastify.pool.query(
      `UPDATE conversation_members
       -- 已读游标只能前进，不能被旧请求/旧事件回退。
       SET last_read_message_id = GREATEST(COALESCE(last_read_message_id, 0), $3)
       WHERE conversation_id = $1 AND user_id = $2
       RETURNING last_read_message_id`,
      [convId, userId, last_read_message_id]
    )

    const confirmedLastReadMessageId = Number(result.rows[0].last_read_message_id)

    fastify.broadcast(userId, {
      type: 'conversation.updated',
      payload: { conversation_id: convId, last_read_message_id: confirmedLastReadMessageId },
    }).catch((err: unknown) => fastify.log.error(err, 'broadcast failed'))

    return reply.status(200).send({ last_read_message_id: confirmedLastReadMessageId })
  })
}

export default conversationRoutes
