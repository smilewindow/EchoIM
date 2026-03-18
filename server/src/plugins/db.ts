import fp from 'fastify-plugin'
import pg from 'pg'
import type { FastifyInstance } from 'fastify'

const { Pool } = pg

declare module 'fastify' {
  interface FastifyInstance {
    pool: pg.Pool
  }
}

export default fp(async function dbPlugin(fastify: FastifyInstance) {
  const connectionString = process.env['DATABASE_URL']
  if (!connectionString) {
    throw new Error('DATABASE_URL environment variable is required')
  }

  const pool = new Pool({ connectionString })

  fastify.decorate('pool', pool)
  fastify.addHook('onClose', () => pool.end())
})
