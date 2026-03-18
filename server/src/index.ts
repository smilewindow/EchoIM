import dotenv from 'dotenv'
import { fileURLToPath } from 'url'
import path from 'path'

// Load .env from the monorepo root, regardless of cwd
dotenv.config({ path: path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../.env') })

// Fail fast if required env vars are missing
if (!process.env['DATABASE_URL']) {
  console.error('ERROR: DATABASE_URL environment variable is required')
  process.exit(1)
}
if (!process.env['JWT_SECRET']) {
  console.error('ERROR: JWT_SECRET environment variable is required')
  process.exit(1)
}

import { buildApp } from './app.js'

const start = async () => {
  const app = await buildApp({ logger: true })
  try {
    // Verify DB connectivity before accepting traffic
    await app.pool.query('SELECT 1')
    app.log.info('Database connection verified')

    await app.listen({ port: Number(process.env['PORT'] ?? 3000), host: '0.0.0.0' })
  } catch (err) {
    app.log.error(err)
    process.exit(1)
  }
}

start()
