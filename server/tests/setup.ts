import dotenv from 'dotenv'
import path from 'path'
import { fileURLToPath } from 'url'
import pg from 'pg'
import { Redis } from 'ioredis'
import { runMigrations, MIGRATIONS_DIR } from '../src/db/migrations-runner.js'

// Load .env so DATABASE_URL is available in the main (globalSetup) process
dotenv.config({ path: path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../.env') })

const { Pool } = pg

const TEST_DB = 'echoim_test'

function buildTestDbUrl(): string {
  const base = process.env['DATABASE_URL']
  if (!base) throw new Error('DATABASE_URL must be set in .env before running tests')
  // Replace the database name at the end of the URL (after the last /)
  return base.replace(/\/[^/]+$/, `/${TEST_DB}`)
}

export const TEST_DB_URL = buildTestDbUrl()

export async function setup() {
  // Derive admin URL (same credentials, dev database) to create the test DB
  const adminUrl = process.env['DATABASE_URL']!

  const adminPool = new Pool({ connectionString: adminUrl })
  try {
    const { rows } = await adminPool.query(
      `SELECT 1 FROM pg_database WHERE datname = $1`,
      [TEST_DB],
    )
    if (rows.length === 0) {
      await adminPool.query(`CREATE DATABASE ${TEST_DB}`)
    }
  } finally {
    await adminPool.end()
  }

  const testPool = new Pool({ connectionString: TEST_DB_URL })
  try {
    await runMigrations(testPool, MIGRATIONS_DIR)
  } finally {
    await testPool.end()
  }

  // Verify Redis connectivity (use DB 1 for test isolation)
  const redisUrl = process.env['TEST_REDIS_URL'] ?? 'redis://localhost:6379/1'
  const redis = new Redis(redisUrl, { lazyConnect: true })
  // Suppress ioredis' unhandled error log so only our message shows on failure
  redis.on('error', () => {})
  try {
    await redis.connect()
    await redis.ping()
  } catch {
    redis.disconnect()
    throw new Error(
      `Redis is not reachable at ${redisUrl}. ` +
      'Tests require a running Redis instance. ' +
      'Run "docker compose up redis" or set TEST_REDIS_URL.',
    )
  }
  redis.disconnect()
}
