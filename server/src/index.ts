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

if (!process.env['INVITE_CODES']) {
  console.warn('WARN: INVITE_CODES is not set — all registration is disabled')
}

if (!process.env['REDIS_URL']) {
  console.warn('WARN: REDIS_URL is not set — using default redis://localhost:6379')
}

import { buildApp } from './app.js'

const start = async () => {
  const app = await buildApp({ logger: true })

  // 把 SIGTERM/SIGINT 接到 fastify.close()，触发 preClose hook 完成
  // WS 优雅下线（presence 清理 + 广播 offline）。Node.js 默认收到这些信号
  // 就直接终止进程，如果不手动 wire 起来，preClose hook 永远不会被调用。
  // 容器编排（docker / k8s）停止 Pod 时先发 SIGTERM，超过 grace 窗口后才
  // 发 SIGKILL，这段窗口里我们需要尽快把 offline 事件广播出去。
  const shutdown = async (signal: NodeJS.Signals) => {
    app.log.info({ signal }, 'received shutdown signal, closing gracefully')
    try {
      await app.close()
      process.exit(0)
    } catch (err) {
      app.log.error(err, 'graceful shutdown failed')
      process.exit(1)
    }
  }
  process.once('SIGTERM', (signal) => void shutdown(signal))
  process.once('SIGINT', (signal) => void shutdown(signal))

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
