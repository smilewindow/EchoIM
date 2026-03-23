const {
  E2E_DATABASE_URL,
  E2E_SERVER_PORT,
  setupE2EDatabase,
} = require('./config.js')

async function main() {
  // 先确保 e2e 专用库存在且 migration 已完成，再启动后端。
  await setupE2EDatabase()

  process.env.DATABASE_URL = E2E_DATABASE_URL
  process.env.PORT = String(E2E_SERVER_PORT)

  await import('../server/src/index.ts')
}

main().catch((error) => {
  console.error('Failed to start e2e server:', error)
  process.exit(1)
})
