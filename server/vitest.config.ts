import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    globalSetup: ['tests/setup.ts'],
    setupFiles: ['tests/env-setup.ts'],
    fileParallelism: false,
    hookTimeout: 30000,
  },
})
