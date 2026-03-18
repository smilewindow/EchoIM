import dotenv from 'dotenv'
import path from 'path'
import { fileURLToPath } from 'url'
import pg from 'pg'
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
}
