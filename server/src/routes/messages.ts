import type { FastifyPluginAsync } from 'fastify'
import { authenticate } from '../hooks/authenticate.js'

const messageRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.addHook('preHandler', authenticate)

  fastify.post('/', {
    schema: {
      body: {
        type: 'object',
        additionalProperties: false,
        required: ['recipient_id', 'body'],
        properties: {
          recipient_id: { type: 'integer' },
          body: { type: 'string', minLength: 1 },
        },
      },
    },
  }, async (request, reply) => {
    const { recipient_id, body } = request.body as { recipient_id: number; body: string }
    const sender_id = request.user.id

    // Verify friendship
    const friendCheck = await fastify.pool.query(
      `SELECT id FROM friend_requests
       WHERE status = 'accepted'
         AND ((sender_id = $1 AND recipient_id = $2) OR (sender_id = $2 AND recipient_id = $1))`,
      [sender_id, recipient_id]
    )
    if (friendCheck.rowCount === 0) {
      return reply.status(403).send({ error: 'Not friends' })
    }

    // Find or create conversation + insert message — all in one transaction with advisory lock
    const client = await fastify.pool.connect()
    let msgRow
    try {
      await client.query('BEGIN')

      // Advisory lock keyed on the sorted user pair to prevent duplicate conversations
      const lockKey = Math.min(sender_id, recipient_id) * 1_000_000 + Math.max(sender_id, recipient_id)
      await client.query('SELECT pg_advisory_xact_lock($1)', [lockKey])

      const convCheck = await client.query(
        `SELECT cm1.conversation_id FROM conversation_members cm1
         JOIN conversation_members cm2 ON cm1.conversation_id = cm2.conversation_id
         WHERE cm1.user_id = $1 AND cm2.user_id = $2`,
        [sender_id, recipient_id]
      )

      let conversation_id: number
      if (convCheck.rowCount && convCheck.rowCount > 0) {
        conversation_id = convCheck.rows[0].conversation_id
      } else {
        const convResult = await client.query(
          'INSERT INTO conversations DEFAULT VALUES RETURNING id'
        )
        conversation_id = convResult.rows[0].id
        await client.query(
          'INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2), ($1, $3)',
          [conversation_id, sender_id, recipient_id]
        )
      }

      const msgResult = await client.query(
        'INSERT INTO messages (conversation_id, sender_id, body) VALUES ($1, $2, $3) RETURNING *',
        [conversation_id, sender_id, body]
      )
      msgRow = msgResult.rows[0]

      await client.query('COMMIT')
    } catch (err) {
      await client.query('ROLLBACK')
      throw err
    } finally {
      client.release()
    }

    fastify.broadcast(recipient_id, { type: 'message.new', payload: msgRow })
    fastify.broadcast(sender_id, { type: 'message.new', payload: msgRow })

    return reply.status(201).send(msgRow)
  })
}

export default messageRoutes
