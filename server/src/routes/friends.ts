import type { FastifyPluginAsync } from 'fastify'
import { authenticate } from '../hooks/authenticate.js'

const friendRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.addHook('preHandler', authenticate)

  fastify.get('/', async (request, reply) => {
    const userId = request.user.id
    const result = await fastify.pool.query(
      `SELECT u.id, u.username, u.display_name, u.avatar_url
       FROM friend_requests fr
       JOIN users u ON u.id = CASE
         WHEN fr.sender_id = $1 THEN fr.recipient_id
         ELSE fr.sender_id
       END
       WHERE fr.status = 'accepted'
         AND (fr.sender_id = $1 OR fr.recipient_id = $1)
       ORDER BY u.username`,
      [userId]
    )
    return reply.status(200).send(result.rows)
  })
}

export default friendRoutes
