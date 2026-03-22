import { test, expect } from '@playwright/test'
import { seedUser, cleanDatabase } from './helpers'

test.beforeEach(async () => {
  await cleanDatabase()
})

test('register new user → redirected to home', async ({ page }) => {
  await page.goto('/register')
  await page.locator('#username').fill('alice')
  await page.locator('#email').fill('alice@example.com')
  await page.locator('#password').fill('password123')
  await page.getByRole('button', { name: 'Create account' }).click()
  await page.waitForURL('/')
  // Sidebar should show the logged-in user's name
  await expect(page.getByText('alice')).toBeVisible()
})

test('login with existing credentials → redirected to home', async ({ page }) => {
  await seedUser('bob', 'bob@example.com', 'password123')

  await page.goto('/login')
  await page.locator('#email').fill('bob@example.com')
  await page.locator('#password').fill('password123')
  await page.getByRole('button', { name: 'Sign in' }).click()
  await page.waitForURL('/')
  await expect(page.getByText('bob')).toBeVisible()
})

test('wrong password → shows error message', async ({ page }) => {
  await seedUser('carol', 'carol@example.com', 'password123')

  await page.goto('/login')
  await page.locator('#email').fill('carol@example.com')
  await page.locator('#password').fill('wrongpassword')
  await page.getByRole('button', { name: 'Sign in' }).click()

  // Should stay on login and show an error
  await expect(page).toHaveURL('/login')
  await expect(page.locator('p').filter({ hasText: /invalid|incorrect|failed/i })).toBeVisible()
})

test('wrong email → shows error message', async ({ page }) => {
  await page.goto('/login')
  await page.locator('#email').fill('nobody@example.com')
  await page.locator('#password').fill('password123')
  await page.getByRole('button', { name: 'Sign in' }).click()

  await expect(page).toHaveURL('/login')
  await expect(page.locator('p').filter({ hasText: /invalid|incorrect|failed|not found/i })).toBeVisible()
})
