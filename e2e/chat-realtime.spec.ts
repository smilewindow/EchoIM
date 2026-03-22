import { test, expect, type APIResponse, type Page, type Route } from '@playwright/test'
import {
  seedUser,
  makeFriends,
  loginAs,
  sendMessageApi,
  markConversationRead,
  cleanDatabase,
} from './helpers'

test.beforeEach(async () => {
  await cleanDatabase()
})

function conversationRow(page: Page, username: string) {
  return page
    .locator('.echo-conversation-row')
    .filter({
      has: page.locator('.echo-conversation-name', { hasText: username }),
    })
    .first()
}

function chatMessages(page: Page) {
  return page.locator('.echo-chat-messages')
}

async function openFriendDraft(page: Page, username: string) {
  await page.getByRole('button', { name: 'Friends' }).click()
  await page.locator('.echo-friend-row').filter({ hasText: username }).first().click()
}

async function sendFromComposer(page: Page, body: string) {
  await page.locator('.echo-message-textarea').fill(body)
  await page.locator('.echo-message-textarea').press('Enter')
}

async function scrollChatTo(page: Page, position: 'top' | 'bottom') {
  await chatMessages(page).evaluate((element, target) => {
    const container = element as HTMLDivElement
    container.scrollTop = target === 'top' ? 0 : container.scrollHeight
    container.dispatchEvent(new Event('scroll'))
  }, position)
}

async function getChatStoreMessages(page: Page) {
  return page.evaluate(async () => {
    const win = window as Window & {
      __echoChatStore?: {
        getState: () => {
          messages: Array<{ id: number | string; body: string; _status?: 'pending' | 'failed' }>
        }
      }
    }

    return (win.__echoChatStore?.getState().messages ?? []).map((message) => ({
      id: message.id,
      body: message.body,
      status: message._status ?? null,
    }))
  })
}

async function setDocumentVisibility(page: Page, visibility: 'visible' | 'hidden') {
  await page.evaluate((nextVisibility) => {
    const win = window as Window & {
      __echoSetVisibilityForTest?: (state: 'visible' | 'hidden') => void
    }

    if (!win.__echoSetVisibilityForTest) {
      let currentVisibility: 'visible' | 'hidden' = 'visible'
      let focused = true

      Object.defineProperty(document, 'visibilityState', {
        configurable: true,
        get: () => currentVisibility,
      })

      document.hasFocus = () => focused

      win.__echoSetVisibilityForTest = (state) => {
        currentVisibility = state
        focused = state === 'visible'
        document.dispatchEvent(new Event('visibilitychange'))
        if (focused) {
          window.dispatchEvent(new Event('focus'))
        }
      }
    }

    win.__echoSetVisibilityForTest(nextVisibility)
  }, visibility)
}

test('user A typing causes user B to see the typing indicator', async ({ browser }) => {
  const alice = await seedUser('alice', 'alice@example.com', 'password123')
  const bob = await seedUser('bob', 'bob@example.com', 'password123')
  await makeFriends(alice.token, bob.token, bob.id)

  const ctxA = await browser.newContext()
  const ctxB = await browser.newContext()
  const pageA = await ctxA.newPage()
  const pageB = await ctxB.newPage()

  await loginAs(pageA, alice.email, 'password123')
  await loginAs(pageB, bob.email, 'password123')

  await openFriendDraft(pageA, 'bob')
  await sendFromComposer(pageA, 'hi')

  const aliceRow = conversationRow(pageB, 'alice')
  await expect(aliceRow).toBeVisible({ timeout: 8_000 })
  await aliceRow.click()

  await pageA.locator('.echo-message-textarea').fill('I am typing right now...')
  await expect(pageB.locator('.echo-typing-indicator')).toBeVisible({ timeout: 8_000 })

  await ctxA.close()
  await ctxB.close()
})

test('user B goes offline and user A sees the presence dot update', async ({ browser }) => {
  const alice = await seedUser('alice', 'alice@example.com', 'password123')
  const bob = await seedUser('bob', 'bob@example.com', 'password123')
  await makeFriends(alice.token, bob.token, bob.id)

  const ctxA = await browser.newContext()
  const ctxB = await browser.newContext()
  const pageA = await ctxA.newPage()
  const pageB = await ctxB.newPage()

  await loginAs(pageA, alice.email, 'password123')
  await loginAs(pageB, bob.email, 'password123')

  await openFriendDraft(pageA, 'bob')
  await expect(pageA.locator('.echo-presence-dot--online')).toBeVisible({ timeout: 8_000 })

  await ctxB.close()
  await expect(pageA.locator('.echo-presence-dot--offline')).toBeVisible({ timeout: 10_000 })

  await ctxA.close()
})

test('active chat keeps unread when scrolled away from bottom, then clears after scrolling back', async ({
  browser,
}) => {
  const alice = await seedUser('alice', 'alice@example.com', 'password123')
  const bob = await seedUser('bob', 'bob@example.com', 'password123')
  await makeFriends(alice.token, bob.token, bob.id)

  // 先造一段足够长的历史，确保聊天窗口可以滚动。
  let conversationId: number | null = null
  for (let i = 1; i <= 30; i++) {
    const message = await sendMessageApi(bob.token, alice.id, `history ${i}`)
    conversationId ??= message.conversation_id
  }
  await markConversationRead(alice.token, conversationId!)

  const ctxA = await browser.newContext()
  const pageA = await ctxA.newPage()
  await loginAs(pageA, alice.email, 'password123')

  const bobRow = conversationRow(pageA, 'bob')
  await expect(bobRow).toBeVisible({ timeout: 8_000 })
  await bobRow.click()
  await expect(chatMessages(pageA)).toContainText('history 30', { timeout: 8_000 })

  await pageA.bringToFront()
  await scrollChatTo(pageA, 'bottom')
  await expect(bobRow.locator('.echo-badge')).not.toBeVisible()

  await scrollChatTo(pageA, 'top')
  await sendMessageApi(bob.token, alice.id, 'off-screen unread')

  await expect(bobRow.locator('.echo-badge')).toHaveText('1', { timeout: 8_000 })

  await pageA.bringToFront()
  await scrollChatTo(pageA, 'bottom')
  await expect(chatMessages(pageA)).toContainText('off-screen unread', { timeout: 10_000 })
  await expect(bobRow.locator('.echo-badge')).not.toBeVisible({ timeout: 10_000 })

  await ctxA.close()
})

test('hidden tab keeps unread until the conversation becomes visible again', async ({ browser }) => {
  const alice = await seedUser('alice', 'alice@example.com', 'password123')
  const bob = await seedUser('bob', 'bob@example.com', 'password123')
  await makeFriends(alice.token, bob.token, bob.id)

  const seedMessage = await sendMessageApi(bob.token, alice.id, 'history before hiding')
  await markConversationRead(alice.token, seedMessage.conversation_id)

  const ctxA = await browser.newContext()
  const pageA = await ctxA.newPage()
  await loginAs(pageA, alice.email, 'password123')

  const bobRow = conversationRow(pageA, 'bob')
  await expect(bobRow).toBeVisible({ timeout: 8_000 })
  await bobRow.click()
  await expect(chatMessages(pageA)).toContainText('history before hiding', { timeout: 8_000 })
  await expect(bobRow.locator('.echo-badge')).not.toBeVisible()

  await setDocumentVisibility(pageA, 'hidden')
  await expect.poll(async () => pageA.evaluate(() => document.visibilityState)).toBe('hidden')

  await sendMessageApi(bob.token, alice.id, 'hidden tab unread')

  await expect(bobRow.locator('.echo-badge')).toHaveText('1', { timeout: 8_000 })

  await setDocumentVisibility(pageA, 'visible')
  await pageA.bringToFront()
  await expect.poll(async () => pageA.evaluate(() => document.visibilityState)).toBe('visible')
  await expect(chatMessages(pageA)).toContainText('hidden tab unread', { timeout: 10_000 })
  await expect(bobRow.locator('.echo-badge')).not.toBeVisible({ timeout: 10_000 })

  await ctxA.close()
})

test('sending the same body twice keeps each optimistic message paired with its own confirmation', async ({
  browser,
}) => {
  const duplicateBody = 'same message, twice'
  const alice = await seedUser('alice', 'alice@example.com', 'password123')
  const bob = await seedUser('bob', 'bob@example.com', 'password123')
  await makeFriends(alice.token, bob.token, bob.id)

  const ctxA = await browser.newContext()
  await ctxA.addInitScript((targetBody) => {
    const NativeWebSocket = window.WebSocket

    class ReorderedWebSocket extends NativeWebSocket {
      __echoBufferedMessage: MessageEvent<string> | null = null
      __echoOnMessage: ((this: WebSocket, ev: MessageEvent<string>) => unknown) | null = null
      __echoReordered = false

      constructor(url: string | URL, protocols?: string | string[]) {
        super(url, protocols)

        super.addEventListener('message', (event) => {
          if (!this.__echoOnMessage) return

          try {
            const parsed = JSON.parse(event.data) as {
              type?: string
              payload?: { body?: string; client_temp_id?: string }
            }
            const shouldReorder =
              !this.__echoReordered &&
              parsed.type === 'message.new' &&
              parsed.payload?.body === targetBody &&
              typeof parsed.payload.client_temp_id === 'string'

            if (shouldReorder) {
              const clonedEvent = new MessageEvent('message', { data: event.data })

              if (!this.__echoBufferedMessage) {
                this.__echoBufferedMessage = clonedEvent
                return
              }

              const firstEvent = this.__echoBufferedMessage
              this.__echoBufferedMessage = null
              this.__echoReordered = true
              this.__echoOnMessage.call(this, clonedEvent)
              queueMicrotask(() => {
                if (this.__echoOnMessage) {
                  this.__echoOnMessage.call(this, firstEvent)
                }
              })
              return
            }
          } catch {
            // ignore malformed messages
          }

          this.__echoOnMessage.call(this, event as MessageEvent<string>)
        })
      }

      get onmessage() {
        return this.__echoOnMessage
      }

      set onmessage(handler) {
        this.__echoOnMessage = handler
      }
    }

    window.WebSocket = ReorderedWebSocket
  }, duplicateBody)

  const pageA = await ctxA.newPage()
  const heldResponses: Array<{
    body: Buffer
    messageId: number
    response: APIResponse
    route: Route
  }> = []

  await pageA.route('**/api/messages', async (route) => {
    if (route.request().method() !== 'POST') {
      await route.continue()
      return
    }

    const payload = route.request().postDataJSON() as { body?: string }
    if (payload.body !== duplicateBody || heldResponses.length >= 2) {
      await route.continue()
      return
    }

    const response = await route.fetch()
    const body = await response.body()
    const parsed = JSON.parse(body.toString()) as { id: number }
    heldResponses.push({ route, response, body, messageId: parsed.id })
  })

  try {
    await loginAs(pageA, alice.email, 'password123')
    await openFriendDraft(pageA, 'bob')
    await expect(pageA.locator('.echo-chat-empty')).toBeVisible()

    await sendFromComposer(pageA, duplicateBody)
    await sendFromComposer(pageA, duplicateBody)

    await expect.poll(() => heldResponses.length, { timeout: 10_000 }).toBe(2)

    await expect.poll(async () => {
      const messages = await getChatStoreMessages(pageA)
      return messages
        .filter((message) => message.body === duplicateBody)
        .map((message) => ({ id: message.id, status: message.status }))
    }, { timeout: 10_000 }).toEqual([
      { id: heldResponses[0].messageId, status: null },
      { id: heldResponses[1].messageId, status: null },
    ])
  } finally {
    await Promise.all(
      heldResponses.map(({ route, response, body }) => route.fulfill({ response, body })),
    )
  }

  await expect(pageA.locator('.echo-bubble--pending')).toHaveCount(0)
  await ctxA.close()
})

test('missed messages appear after reconnect for an existing conversation', async ({ browser }) => {
  test.setTimeout(60_000)

  const alice = await seedUser('alice', 'alice@example.com', 'password123')
  const bob = await seedUser('bob', 'bob@example.com', 'password123')
  await makeFriends(alice.token, bob.token, bob.id)

  const ctxA = await browser.newContext()
  const pageA = await ctxA.newPage()
  await loginAs(pageA, alice.email, 'password123')

  await openFriendDraft(pageA, 'bob')
  await sendFromComposer(pageA, 'hi Bob')
  await expect(chatMessages(pageA)).toContainText('hi Bob', { timeout: 8_000 })

  await ctxA.setOffline(true)
  await pageA.waitForTimeout(800)

  await sendMessageApi(bob.token, alice.id, 'missed message 1')
  await sendMessageApi(bob.token, alice.id, 'missed message 2')
  await sendMessageApi(bob.token, alice.id, 'missed message 3')

  await ctxA.setOffline(false)

  await expect.poll(
    async () =>
      (await getChatStoreMessages(pageA)).filter((message) =>
        message.body.startsWith('missed message '),
      ).length,
    { timeout: 20_000 },
  ).toBe(3)
  await expect(chatMessages(pageA)).toContainText('missed message 1')
  await expect(chatMessages(pageA)).toContainText('missed message 3')

  await ctxA.close()
})

test('reconnect restores all missed messages even when more than 50 arrive', async ({ browser }) => {
  test.setTimeout(150_000)

  const alice = await seedUser('alice', 'alice@example.com', 'password123')
  const bob = await seedUser('bob', 'bob@example.com', 'password123')
  await makeFriends(alice.token, bob.token, bob.id)

  const ctxA = await browser.newContext()
  const pageA = await ctxA.newPage()
  await loginAs(pageA, alice.email, 'password123')

  await openFriendDraft(pageA, 'bob')
  await sendFromComposer(pageA, 'starting message')
  await expect(chatMessages(pageA)).toContainText('starting message', { timeout: 8_000 })

  await ctxA.setOffline(true)
  await pageA.waitForTimeout(800)

  const totalMissed = 52
  // 一次性并发发送，把断线窗口压到最短，避免重连退避把这条用例拖成偶发超时。
  await Promise.all(
    Array.from({ length: totalMissed }, (_, index) =>
      sendMessageApi(bob.token, alice.id, `bulk message ${index + 1}`),
    ),
  )

  await ctxA.setOffline(false)

  await expect.poll(
    async () =>
      (await getChatStoreMessages(pageA)).filter((message) =>
        message.body.startsWith('bulk message '),
      ).length,
    { timeout: 60_000 },
  ).toBe(totalMissed)
  await expect(chatMessages(pageA)).toContainText('bulk message 1')
  await expect(chatMessages(pageA)).toContainText(`bulk message ${totalMissed}`)

  await ctxA.close()
})

test('first incoming message promotes the open draft chat without manual refresh', async ({
  browser,
}) => {
  const alice = await seedUser('alice', 'alice@example.com', 'password123')
  const bob = await seedUser('bob', 'bob@example.com', 'password123')
  await makeFriends(alice.token, bob.token, bob.id)

  const ctxA = await browser.newContext()
  const pageA = await ctxA.newPage()
  await loginAs(pageA, alice.email, 'password123')

  await openFriendDraft(pageA, 'bob')
  await expect(pageA.locator('.echo-chat-empty')).toBeVisible()

  await sendMessageApi(bob.token, alice.id, 'Hello from Bob!')

  await expect(chatMessages(pageA)).toContainText('Hello from Bob!', { timeout: 10_000 })
  await expect(pageA.locator('.echo-chat-peer-name')).toHaveText('bob')

  await ctxA.close()
})

test('offline first message promotes the draft chat after reconnect', async ({ browser }) => {
  test.setTimeout(60_000)

  const alice = await seedUser('alice', 'alice@example.com', 'password123')
  const bob = await seedUser('bob', 'bob@example.com', 'password123')
  await makeFriends(alice.token, bob.token, bob.id)

  const ctxA = await browser.newContext()
  const pageA = await ctxA.newPage()
  await loginAs(pageA, alice.email, 'password123')

  await openFriendDraft(pageA, 'bob')
  await expect(pageA.locator('.echo-chat-empty')).toBeVisible()

  await ctxA.setOffline(true)
  await pageA.waitForTimeout(800)

  await sendMessageApi(bob.token, alice.id, 'Hello while offline!')
  await pageA.waitForTimeout(500)
  await expect(pageA.locator('.echo-chat-empty')).toBeVisible()

  await ctxA.setOffline(false)

  await expect(chatMessages(pageA)).toContainText('Hello while offline!', { timeout: 15_000 })
  await expect(pageA.locator('.echo-chat-peer-name')).toHaveText('bob')
  await expect(conversationRow(pageA, 'bob')).toHaveClass(/echo-conversation-row--active/)

  await ctxA.close()
})

test('first message from another friend does not get routed into the already-open conversation', async ({
  browser,
}) => {
  const alice = await seedUser('alice', 'alice@example.com', 'password123')
  const bob = await seedUser('bob', 'bob@example.com', 'password123')
  const charlie = await seedUser('charlie', 'charlie@example.com', 'password123')
  await makeFriends(alice.token, bob.token, bob.id)
  await makeFriends(alice.token, charlie.token, charlie.id)

  const ctxA = await browser.newContext()
  const pageA = await ctxA.newPage()
  await loginAs(pageA, alice.email, 'password123')

  await openFriendDraft(pageA, 'bob')
  await sendFromComposer(pageA, 'Hi Bob')
  await expect(chatMessages(pageA)).toContainText('Hi Bob', { timeout: 8_000 })
  await expect(pageA.locator('.echo-chat-peer-name')).toHaveText('bob')

  await sendMessageApi(charlie.token, alice.id, 'Hello from Charlie!')

  await expect(pageA.locator('.echo-chat-peer-name')).toHaveText('bob')
  await expect(chatMessages(pageA)).not.toContainText('Hello from Charlie!')

  const charlieRow = conversationRow(pageA, 'charlie')
  await expect(charlieRow).toBeVisible({ timeout: 10_000 })
  await expect(charlieRow).toContainText('Hello from Charlie!')

  await ctxA.close()
})

test('presence dot corrects to offline for friend who disconnected during WS outage', async ({
  browser,
}) => {
  const alice = await seedUser('alice', 'alice@example.com', 'password123')
  const bob = await seedUser('bob', 'bob@example.com', 'password123')
  await makeFriends(alice.token, bob.token, bob.id)

  const ctxA = await browser.newContext()
  const ctxB = await browser.newContext()
  const pageA = await ctxA.newPage()
  const pageB = await ctxB.newPage()

  await loginAs(pageA, alice.email, 'password123')
  await loginAs(pageB, bob.email, 'password123')

  await openFriendDraft(pageA, 'bob')
  await expect(pageA.locator('.echo-presence-dot--online')).toBeVisible({ timeout: 8_000 })

  await ctxA.setOffline(true)
  await pageA.waitForTimeout(800)

  await ctxB.close()
  await ctxA.setOffline(false)

  await expect(pageA.locator('.echo-presence-dot--offline')).toBeVisible({ timeout: 15_000 })

  await ctxA.close()
})
