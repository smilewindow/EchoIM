import { test, expect } from '@playwright/test'
import { seedUser, makeFriends, loginAs, cleanDatabase } from './helpers'

test.beforeEach(async () => {
  await cleanDatabase()
})

test('user A sends a message and user B receives it in real time', async ({ browser }) => {
  const alice = await seedUser('alice', 'alice@example.com', 'password123')
  const bob = await seedUser('bob', 'bob@example.com', 'password123')
  await makeFriends(alice.token, bob.token, bob.id)

  const ctxA = await browser.newContext()
  const ctxB = await browser.newContext()
  const pageA = await ctxA.newPage()
  const pageB = await ctxB.newPage()

  await loginAs(pageA, alice.email, 'password123')
  await loginAs(pageB, bob.email, 'password123')

  await pageA.getByRole('button', { name: 'Friends' }).click()
  await pageA.locator('.echo-friend-row').filter({ hasText: 'bob' }).first().click()

  const message = 'Hello Bob, can you see this?'
  await pageA.locator('.echo-message-textarea').fill(message)
  await pageA.locator('.echo-message-textarea').press('Enter')

  const aliceRow = pageB
    .locator('.echo-conversation-row')
    .filter({ has: pageB.locator('.echo-conversation-name', { hasText: 'alice' }) })
    .first()

  await expect(aliceRow).toBeVisible({ timeout: 8_000 })
  await aliceRow.click()
  await expect(pageB.locator('.echo-chat-messages')).toContainText(message, { timeout: 8_000 })

  await ctxA.close()
  await ctxB.close()
})
