import { defineConfig, devices } from '@playwright/test'
import {
  E2E_CLIENT_ORIGIN,
  E2E_CLIENT_PORT,
  E2E_SERVER_ORIGIN,
} from './e2e/config.js'

export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  expect: { timeout: 5_000 },
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: 'html',

  use: {
    baseURL: E2E_CLIENT_ORIGIN,
    trace: 'on-first-retry',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  webServer: [
    {
      command: './server/node_modules/.bin/tsx e2e/start-server.js',
      url: `${E2E_SERVER_ORIGIN}/healthz`,
      reuseExistingServer: false,
      timeout: 30_000,
    },
    {
      command: `npm run dev --prefix client -- --host 127.0.0.1 --port ${E2E_CLIENT_PORT}`,
      url: E2E_CLIENT_ORIGIN,
      reuseExistingServer: false,
      timeout: 30_000,
      env: {
        ECHOIM_API_ORIGIN: E2E_SERVER_ORIGIN,
      },
    },
  ],
})
