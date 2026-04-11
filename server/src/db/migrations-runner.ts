import path from 'path'
import fs from 'fs'
import pg from 'pg'

// 跨实例串行化迁移执行：多个 server 副本同时 fresh-start 时，若不加锁，
// 它们会各自读到空的 schema_migrations 后并发执行 DDL + INSERT，导致主键
// 冲突或 DDL race。用一个固定 bigint 作为 advisory lock 的 key，session
// 级锁在 client.release() 之前显式释放，pool.end() 也会最终丢弃。
const MIGRATION_LOCK_KEY = 4959_663_001

export async function runMigrations(pool: pg.Pool, migrationsDir: string) {
  const client = await pool.connect()
  let locked = false
  try {
    await client.query('SELECT pg_advisory_lock($1)', [MIGRATION_LOCK_KEY])
    locked = true

    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        filename TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `)

    const { rows } = await client.query<{ filename: string }>(
      'SELECT filename FROM schema_migrations ORDER BY filename',
    )
    const applied = new Set(rows.map((r) => r.filename))

    const files = fs
      .readdirSync(migrationsDir)
      .filter((f) => f.endsWith('.sql'))
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

    console.log('Migrations complete.')
  } catch (err) {
    await client.query('ROLLBACK')
    throw err
  } finally {
    if (locked) {
      await client
        .query('SELECT pg_advisory_unlock($1)', [MIGRATION_LOCK_KEY])
        .catch(() => {
          // 释放失败不覆盖原始错误；pool 关闭时会话结束后锁也会被丢弃。
        })
    }
    client.release()
  }
}

export const MIGRATIONS_DIR = path.resolve(
  new URL('.', import.meta.url).pathname,
  'migrations',
)
