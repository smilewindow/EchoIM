import Fastify from 'fastify'
import type { FastifyError, FastifyServerOptions } from 'fastify'
import dbPlugin from './plugins/db.js'
import wsPlugin from './plugins/ws.js'
import { registerAuthDecorator } from './hooks/authenticate.js'
import authRoutes from './routes/auth.js'
import userRoutes from './routes/users.js'
import friendRequestRoutes from './routes/friend-requests.js'
import friendRoutes from './routes/friends.js'
import messageRoutes from './routes/messages.js'
import conversationRoutes from './routes/conversations.js'

export async function buildApp(opts: FastifyServerOptions = {}) {
  const app = Fastify({
    logger: false,
    ...opts,
    ajv: { customOptions: { removeAdditional: false } },
  })

  registerAuthDecorator(app)

  app.setErrorHandler((err: FastifyError, _request, reply) => {
    const statusCode = err.statusCode ?? 500
    if (statusCode >= 400 && statusCode < 500) {
      return reply.status(statusCode).send({ error: err.message })
    }
    app.log.error(err)
    return reply.status(500).send({ error: 'Internal server error' })
  })

  app.get('/healthz', async () => ({ status: 'ok' }))

  await app.register(dbPlugin)
  await app.register(wsPlugin)
  await app.register(authRoutes, { prefix: '/api/auth' })
  await app.register(userRoutes, { prefix: '/api/users' })
  await app.register(friendRequestRoutes, { prefix: '/api/friend-requests' })
  await app.register(friendRoutes, { prefix: '/api/friends' })
  await app.register(messageRoutes, { prefix: '/api/messages' })
  await app.register(conversationRoutes, { prefix: '/api/conversations' })

  return app
}
