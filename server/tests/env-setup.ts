// Sets test env vars in each worker process (globalSetup mutations don't propagate to workers).
// Derives the test database URL from DATABASE_URL in .env to stay in sync with local config.
import dotenv from 'dotenv'
import path from 'path'
import { fileURLToPath } from 'url'

dotenv.config({ path: path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../.env') })

const base = process.env['DATABASE_URL']
if (!base) throw new Error('DATABASE_URL must be set in .env before running tests')

process.env['DATABASE_URL'] = base.replace(/\/[^/]+$/, '/echoim_test')
process.env['JWT_SECRET'] = process.env['JWT_SECRET'] ?? 'test-secret-for-vitest'
