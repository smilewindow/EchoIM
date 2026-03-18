import dotenv from 'dotenv'
import { fileURLToPath } from 'url'
import path from 'path'
import pg from 'pg'
import { runMigrations, MIGRATIONS_DIR } from './migrations-runner.js'

dotenv.config({ path: path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../.env') })

const { Pool } = pg

async function migrate() {
  const pool = new Pool({ connectionString: process.env['DATABASE_URL'] })
  try {
    await runMigrations(pool, MIGRATIONS_DIR)
  } catch (err) {
    console.error('Migration failed:', err)
    process.exit(1)
  } finally {
    await pool.end()
  }
}

migrate()
