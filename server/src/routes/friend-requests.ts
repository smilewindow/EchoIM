import type { FastifyPluginAsync } from 'fastify'
import { authenticate } from '../hooks/authenticate.js'

const friendRequestRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.addHook('preHandler', authenticate)

  fastify.post('/', {
    schema: {
      body: {
        type: 'object',
        additionalProperties: false,
        required: ['recipient_id'],
        properties: {
          recipient_id: { type: 'integer' },
        },
      },
    },
  }, async (request, reply) => {
    const { recipient_id } = request.body as { recipient_id: number }
    const senderId = request.user.id

    if (recipient_id === senderId) {
      return reply.status(400).send({ error: 'Cannot send friend request to yourself' })
    }

    const recipientCheck = await fastify.pool.query(
      'SELECT id, username, display_name, avatar_url FROM users WHERE id = $1',
      [recipient_id]
    )
    if (recipientCheck.rowCount === 0) {
      return reply.status(404).send({ error: 'Recipient not found' })
    }

    try {
      const result = await fastify.pool.query(
        `INSERT INTO friend_requests (sender_id, recipient_id, status)
         VALUES ($1, $2, 'pending')
         RETURNING *`,
        [senderId, recipient_id]
      )
      const row = result.rows[0]
      const senderInfo = await fastify.pool.query(
        'SELECT username, display_name, avatar_url FROM users WHERE id = $1',
        [senderId]
      )
      const recipientInfo = recipientCheck.rows[0]
      // 接收方看到发送者信息；发送方看到接收者信息（与 /friend-requests/sent 结构一致）
      fastify.broadcast(recipient_id, { type: 'friend_request.new', payload: { ...row, ...senderInfo.rows[0] } })
        .catch((err: unknown) => fastify.log.error(err, 'broadcast failed'))
      fastify.broadcast(senderId, { type: 'friend_request.new', payload: { ...row, ...recipientInfo } })
        .catch((err: unknown) => fastify.log.error(err, 'broadcast failed'))
      return reply.status(201).send(row)
    } catch (err: unknown) {
      if (typeof err === 'object' && err !== null && (err as { code?: string }).code === '23505') {
        return reply.status(409).send({ error: 'Friend request already exists' })
      }
      throw err
    }
  })

  fastify.get('/', async (request, reply) => {
    const result = await fastify.pool.query(
      `SELECT fr.id, fr.sender_id, fr.recipient_id, fr.status, fr.created_at, fr.updated_at,
              u.username, u.display_name, u.avatar_url
       FROM friend_requests fr
       JOIN users u ON u.id = fr.sender_id
       WHERE fr.recipient_id = $1 AND fr.status = 'pending'
       ORDER BY fr.created_at DESC`,
      [request.user.id]
    )
    return reply.status(200).send(result.rows)
  })

  fastify.get('/sent', async (request, reply) => {
    const result = await fastify.pool.query(
      `SELECT fr.id, fr.sender_id, fr.recipient_id, fr.status, fr.created_at, fr.updated_at,
              u.username, u.display_name, u.avatar_url
       FROM friend_requests fr
       JOIN users u ON u.id = fr.recipient_id
       WHERE fr.sender_id = $1 AND fr.status = 'pending'
       ORDER BY fr.created_at DESC`,
      [request.user.id]
    )
    return reply.status(200).send(result.rows)
  })

  fastify.get('/history', async (request, reply) => {
    const userId = request.user.id
    const result = await fastify.pool.query(
      `SELECT fr.id, fr.sender_id, fr.recipient_id, fr.status, fr.created_at, fr.updated_at,
              CASE WHEN fr.sender_id = $1 THEN 'sent' ELSE 'received' END AS direction,
              u.username, u.display_name, u.avatar_url
       FROM friend_requests fr
       JOIN users u ON u.id = CASE WHEN fr.sender_id = $1 THEN fr.recipient_id ELSE fr.sender_id END
       WHERE (fr.sender_id = $1 OR fr.recipient_id = $1)
         AND fr.status IN ('accepted', 'declined')
       ORDER BY fr.updated_at DESC`,
      [userId]
    )
    return reply.status(200).send(result.rows)
  })

  fastify.put('/:id', {
    schema: {
      body: {
        type: 'object',
        additionalProperties: false,
        required: ['status'],
        properties: {
          status: { type: 'string', enum: ['accepted', 'declined'] },
        },
      },
    },
  }, async (request, reply) => {
    const { id } = request.params as { id: string }
    const { status } = request.body as { status: 'accepted' | 'declined' }

    const numericId = parseInt(id, 10)
    if (!Number.isInteger(numericId) || numericId <= 0) {
      return reply.status(400).send({ error: 'Invalid id' })
    }

    const result = await fastify.pool.query(
      `UPDATE friend_requests
       SET status = $1, updated_at = NOW()
       WHERE id = $2 AND recipient_id = $3 AND status = 'pending'
       RETURNING *`,
      [status, numericId, request.user.id]
    )

    if (result.rowCount === 0) {
      return reply.status(404).send({ error: 'Not found or already resolved' })
    }

    const row = result.rows[0]
    const [responderInfo, senderInfo] = await Promise.all([
      fastify.pool.query('SELECT username, display_name, avatar_url FROM users WHERE id = $1', [request.user.id]),
      fastify.pool.query('SELECT username, display_name, avatar_url FROM users WHERE id = $1', [row.sender_id]),
    ])
    const eventType = row.status === 'accepted' ? 'friend_request.accepted' : 'friend_request.declined'
    // 原始发送方看到操作方（responder）的信息；操作方看到原始发送方的信息
    fastify.broadcast(row.sender_id, { type: eventType, payload: { ...row, ...responderInfo.rows[0] } })
      .catch((err: unknown) => fastify.log.error(err, 'broadcast failed'))
    fastify.broadcast(request.user.id, { type: eventType, payload: { ...row, ...senderInfo.rows[0] } })
      .catch((err: unknown) => fastify.log.error(err, 'broadcast failed'))

    return reply.status(200).send(row)
  })
}

export default friendRequestRoutes
