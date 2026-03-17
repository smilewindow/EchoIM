import dotenv from 'dotenv'
import { fileURLToPath } from 'url'
import path from 'path'
import Fastify from 'fastify'
import pg from 'pg'

// Load .env from the monorepo root, regardless of cwd
dotenv.config({ path: path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../.env') })

const { Pool } = pg

const pool = new Pool({
  connectionString: process.env['DATABASE_URL'],
})

const app = Fastify({ logger: true })

app.get('/healthz', async (_request, _reply) => {
  return { status: 'ok' }
})

const start = async () => {
  try {
    await pool.query('SELECT 1')
    app.log.info('Database connection verified')

    await app.listen({ port: Number(process.env['PORT'] ?? 3000), host: '0.0.0.0' })
  } catch (err) {
    app.log.error(err)
    process.exit(1)
  }
}

start()
