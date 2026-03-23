const fs = require('fs')
const path = require('path')
const pg = require('pg')

const { Pool } = pg

const ROOT_ENV_PATH = path.resolve(__dirname, '../.env')
const MIGRATIONS_DIR = path.resolve(__dirname, '../server/src/db/migrations')

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return
  }

  const content = fs.readFileSync(filePath, 'utf8')
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim()
    if (!line || line.startsWith('#')) {
      continue
    }

    const separatorIndex = line.indexOf('=')
    if (separatorIndex <= 0) {
      continue
    }

    const key = line.slice(0, separatorIndex).trim()
    let value = line.slice(separatorIndex + 1).trim()

    if (!key || process.env[key] !== undefined) {
      continue
    }

    // 这里只处理仓库当前会用到的简单 .env 语法，避免依赖特定 Node 版本能力。
    if (
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))
    ) {
      value = value.slice(1, -1)
    }

    process.env[key] = value
  }
}

if (!process.env.DATABASE_URL || !process.env.JWT_SECRET) {
  loadEnvFile(ROOT_ENV_PATH)
}

const E2E_DATABASE_NAME = 'echoim_e2e'
const E2E_SERVER_PORT = 3001
const E2E_CLIENT_PORT = 4173
const E2E_SERVER_ORIGIN = `http://127.0.0.1:${E2E_SERVER_PORT}`
const E2E_CLIENT_ORIGIN = `http://127.0.0.1:${E2E_CLIENT_PORT}`

function buildDatabaseUrl(databaseName) {
  const base = process.env.DATABASE_URL
  if (!base) {
    throw new Error('DATABASE_URL must be set in .env before running e2e tests')
  }

  return base.replace(/\/[^/]+$/, `/${databaseName}`)
}

const E2E_DATABASE_URL = buildDatabaseUrl(E2E_DATABASE_NAME)

async function runMigrations(pool, migrationsDir) {
  const client = await pool.connect()
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        filename TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `)

    const { rows } = await client.query(
      'SELECT filename FROM schema_migrations ORDER BY filename',
    )
    const applied = new Set(rows.map((row) => row.filename))

    const files = fs
      .readdirSync(migrationsDir)
      .filter((file) => file.endsWith('.sql'))
      .sort()

    for (const file of files) {
      if (applied.has(file)) {
        console.log(`  skip  ${file}`)
        continue
      }

      const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8')
      await client.query('BEGIN')
      await client.query(sql)
      await client.query('INSERT INTO schema_migrations (filename) VALUES ($1)', [file])
      await client.query('COMMIT')
      console.log(`  apply ${file}`)
    }

    console.log('E2E migrations complete.')
  } catch (error) {
    await client.query('ROLLBACK')
    throw error
  } finally {
    client.release()
  }
}

async function setupE2EDatabase() {
  const adminUrl = process.env.DATABASE_URL
  if (!adminUrl) {
    throw new Error('DATABASE_URL must be set in .env before running e2e tests')
  }

  const adminPool = new Pool({ connectionString: adminUrl })
  try {
    const { rows } = await adminPool.query(
      'SELECT 1 FROM pg_database WHERE datname = $1',
      [E2E_DATABASE_NAME],
    )

    if (rows.length === 0) {
      await adminPool.query(`CREATE DATABASE ${E2E_DATABASE_NAME}`)
    }
  } finally {
    await adminPool.end()
  }

  const e2ePool = new Pool({ connectionString: E2E_DATABASE_URL })
  try {
    await runMigrations(e2ePool, MIGRATIONS_DIR)
  } finally {
    await e2ePool.end()
  }
}

module.exports = {
  E2E_CLIENT_ORIGIN,
  E2E_CLIENT_PORT,
  E2E_DATABASE_NAME,
  E2E_DATABASE_URL,
  E2E_SERVER_ORIGIN,
  E2E_SERVER_PORT,
  buildDatabaseUrl,
  setupE2EDatabase,
}
