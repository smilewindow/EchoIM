import { expect, test } from '@playwright/test'
import { cleanDatabase, loginAs, seedUser } from './helpers'

test.beforeEach(async () => {
  await cleanDatabase()
})

test('logged-in user keeps the selected tab across refresh and profile round-trip', async ({ page }) => {
  await seedUser('tabuser', 'tabuser@example.com', 'password123')

  await loginAs(page, 'tabuser@example.com', 'password123')

  await page.getByRole('button', { name: 'Requests' }).click()
  await expect(page).toHaveURL('/?tab=requests')
  await expect(page.getByText('No requests yet')).toBeVisible()

  await page.reload()
  await expect(page).toHaveURL('/?tab=requests')
  await expect(page.getByText('No requests yet')).toBeVisible()

  await page.getByTitle('Edit profile').click()
  await expect(page).toHaveURL('/profile?tab=requests')

  await page.getByRole('button', { name: 'Back' }).click()
  await expect(page).toHaveURL('/?tab=requests')
  await expect(page.getByText('No requests yet')).toBeVisible()
})

test('unauthenticated visit restores the requested tab after login', async ({ page }) => {
  await seedUser('redirectuser', 'redirectuser@example.com', 'password123')

  await page.goto('/?tab=search')
  await expect(page).toHaveURL(/\/login\?redirect=/)

  await page.locator('#email').fill('redirectuser@example.com')
  await page.locator('#password').fill('password123')
  await page.getByRole('button', { name: 'Sign in' }).click()

  await expect(page).toHaveURL('/?tab=search')
  await expect(page.getByText('Type at least 2 characters to search')).toBeVisible()
})
