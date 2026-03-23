import { create } from 'zustand'
import { toast } from 'sonner'
import { apiFetch } from '@/lib/api'
import { useAuthStore } from '@/stores/auth'

export interface Conversation {
  id: number
  created_at: string
  unread_count: number
  last_message_body: string | null
  last_message_sender_id: number | null
  last_message_at: string | null
  peer_id: number
  peer_username: string
  peer_display_name: string | null
  peer_avatar_url: string | null
}

export interface Message {
  id: number | string
  conversation_id: number
  sender_id: number
  body: string
  created_at: string
  client_temp_id?: string
  _status?: 'pending' | 'failed'
  _tempId?: string
}

export interface PeerInfo {
  id: number
  username: string
  display_name: string | null
  avatar_url: string | null
}

interface ChatState {
  conversations: Conversation[]
  conversationsLoading: boolean
  activeConversationId: number | null
  activePeer: PeerInfo | null
  messages: Message[]
  messagesLoading: boolean
  hasMore: boolean
  typingConversationIds: Set<number>
  lastMessageTimestamp: string | null

  fetchConversations: () => Promise<void>
  selectConversation: (convId: number) => Promise<void>
  selectPeer: (peer: PeerInfo) => void
  loadOlderMessages: () => Promise<void>
  sendMessage: (recipientId: number, body: string) => Promise<void>
  retryMessage: (tempId: string, recipientId: number, body: string) => void
  markRead: (convId: number) => Promise<void>
  clearChat: () => void
  handleIncomingMessage: (message: Message) => void
  handleConversationUpdated: (payload: { conversation_id: number; last_read_at: string }) => void
  handleTypingStart: (conversationId: number) => void
  handleTypingStop: (conversationId: number) => void
  promoteActivePeerConversation: (conversationId?: number) => Promise<boolean>
  refetchMissedMessages: () => Promise<void>
}

let abortController: AbortController | null = null

// Typing auto-clear timeouts keyed by conversation_id (outside Zustand to avoid serialization issues)
const typingTimeouts = new Map<number, ReturnType<typeof setTimeout>>()
const MESSAGE_PAGE_SIZE = 50
const GAP_FILL_MAX_PAGES = 20

function sortConversationsByActivity(conversations: Conversation[]) {
  return [...conversations].sort((a, b) => {
    const at = a.last_message_at ?? a.created_at
    const bt = b.last_message_at ?? b.created_at
    return bt.localeCompare(at)
  })
}

function isSameChatContext(
  state: Pick<ChatState, 'activeConversationId' | 'activePeer'>,
  conversationId: number | null,
  peerId: number | null,
) {
  if (conversationId !== null) {
    return state.activeConversationId === conversationId
  }

  return state.activeConversationId === null && state.activePeer?.id === peerId
}

function replaceOrAppendMessage(messages: Message[], tempId: string, result: Message) {
  // Remove any WS-delivered copy of this message that might have arrived before REST responded
  const deduped = messages.filter((m) => m.id !== result.id || m._tempId === tempId)

  const hasTempMessage = deduped.some((message) => message._tempId === tempId)
  if (hasTempMessage) {
    return deduped.map((message) =>
      message._tempId === tempId ? { ...result } : message,
    )
  }

  if (deduped.some((message) => message.id === result.id)) {
    return deduped
  }

  return [...deduped, result]
}

function normalizeIncomingMessage(message: Message): Message {
  if (!message.client_temp_id) return message

  // 服务端只回传一次 client_temp_id，前端把它映射回本地 pending 标识，避免用 body 猜测匹配。
  return { ...message, _tempId: message.client_temp_id }
}

function findDraftConversation(
  state: Pick<ChatState, 'activeConversationId' | 'activePeer' | 'conversations'>,
  conversationId?: number,
) {
  if (state.activeConversationId !== null || !state.activePeer) return null

  const match = conversationId !== undefined
    ? state.conversations.find((conversation) => conversation.id === conversationId)
    : state.conversations.find((conversation) => conversation.peer_id === state.activePeer?.id)

  if (!match || match.peer_id !== state.activePeer.id) {
    return null
  }

  return match
}

export const useChatStore = create<ChatState>((set, get) => ({
  conversations: [],
  conversationsLoading: false,
  activeConversationId: null,
  activePeer: null,
  messages: [],
  messagesLoading: false,
  hasMore: false,
  typingConversationIds: new Set(),
  lastMessageTimestamp: null,

  fetchConversations: async () => {
    set({ conversationsLoading: true })
    try {
      const data = await apiFetch<Conversation[]>('/conversations')
      set({ conversations: data, conversationsLoading: false })
    } catch {
      set({ conversationsLoading: false })
      toast.error('Failed to load conversations')
    }
  },

  selectConversation: async (convId: number) => {
    // Abort any in-flight message fetch
    abortController?.abort()
    abortController = new AbortController()
    const signal = abortController.signal

    set({ activeConversationId: convId, activePeer: null, messages: [], messagesLoading: true, hasMore: false })

    try {
      const data = await apiFetch<Message[]>(`/conversations/${convId}/messages`, { signal })
      if (signal.aborted) return
      // API returns DESC (newest first); reverse to chronological for display
      set({
        messages: [...data].reverse().map(normalizeIncomingMessage),
        messagesLoading: false,
        hasMore: data.length === MESSAGE_PAGE_SIZE,
      })
    } catch {
      if (signal.aborted) return
      set({ messagesLoading: false })
    }
  },

  selectPeer: (peer: PeerInfo) => {
    const existing = get().conversations.find((c) => c.peer_id === peer.id)
    if (existing) {
      get().selectConversation(existing.id)
    } else {
      abortController?.abort()
      set({ activePeer: peer, activeConversationId: null, messages: [], messagesLoading: false, hasMore: false })
    }
  },

  loadOlderMessages: async () => {
    const { activeConversationId, messages } = get()
    if (!activeConversationId || messages.length === 0) return

    const requestConversationId = activeConversationId
    const oldestId = messages[0].id
    const data = await apiFetch<Message[]>(`/conversations/${activeConversationId}/messages?before=${oldestId}`)
    const state = get()

    // Ignore stale pagination responses after the user changes chats or the window shifts.
    if (
      state.activeConversationId !== requestConversationId ||
      state.messages[0]?.id !== oldestId
    ) {
      return
    }

    const older = [...data].reverse().map(normalizeIncomingMessage)
    set({ messages: [...older, ...state.messages], hasMore: data.length === MESSAGE_PAGE_SIZE })
  },

  sendMessage: async (recipientId: number, body: string) => {
    const tempId = `pending-${crypto.randomUUID()}`
    const { user } = useAuthStore.getState()
    if (!user) return

    const initialState = get()
    const requestConversationId = initialState.activeConversationId
    const requestPeerId = initialState.activePeer?.id ?? null
    const wasNewConversation = requestConversationId === null

    const optimistic: Message = {
      id: tempId,
      conversation_id: requestConversationId ?? -1,
      sender_id: user.id,
      body,
      created_at: new Date().toISOString(),
      _status: 'pending',
      _tempId: tempId,
    }

    set({ messages: [...initialState.messages, optimistic] })

    try {
      const result = normalizeIncomingMessage(await apiFetch<Message>('/messages', {
        method: 'POST',
        body: JSON.stringify({ recipient_id: recipientId, body, client_temp_id: tempId }),
      }))
      const state = get()
      const shouldUpdateActiveMessages = isSameChatContext(
        state,
        requestConversationId,
        requestPeerId,
      )

      // Ignore stale responses after the user navigates to a different chat.
      if (shouldUpdateActiveMessages) {
        set({
          messages: replaceOrAppendMessage(state.messages, tempId, result),
          activeConversationId: wasNewConversation
            ? result.conversation_id
            : state.activeConversationId,
          activePeer: wasNewConversation ? null : state.activePeer,
        })
      }

      // Update conversation list preview
      const convId = result.conversation_id
      const existing = get().conversations.find((c) => c.id === convId)
      if (existing) {
        set({
          conversations: sortConversationsByActivity(
            get().conversations.map((c) =>
              c.id === convId
                ? {
                    ...c,
                    last_message_body: result.body,
                    last_message_at: result.created_at,
                    last_message_sender_id: result.sender_id,
                  }
                : c,
            ),
          ),
        })
      } else if (wasNewConversation) {
        // New conversation created — fetch the full list to get peer info
        get().fetchConversations()
      }
    } catch {
      const state = get()

      if (!isSameChatContext(state, requestConversationId, requestPeerId)) {
        return
      }

      set({
        messages: state.messages.map((message) =>
          message._tempId === tempId ? { ...message, _status: 'failed' } : message,
        ),
      })
      toast.error('Failed to send message')
    }
  },

  retryMessage: (tempId: string, recipientId: number, body: string) => {
    set({ messages: get().messages.filter((m) => m._tempId !== tempId) })
    get().sendMessage(recipientId, body)
  },

  markRead: async (convId: number) => {
    try {
      await apiFetch(`/conversations/${convId}/read`, { method: 'PUT' })
      set({
        conversations: get().conversations.map((c) => (c.id === convId ? { ...c, unread_count: 0 } : c)),
      })
    } catch {
      // ignore
    }
  },

  clearChat: () => {
    abortController?.abort()
    abortController = null
    set({
      activeConversationId: null,
      activePeer: null,
      messages: [],
      messagesLoading: false,
      hasMore: false,
    })
  },

  handleIncomingMessage: (message: Message) => {
    const incoming = normalizeIncomingMessage(message)
    const currentUserId = useAuthStore.getState().user?.id
    const state = get()
    const convId = incoming.conversation_id
    const isActiveConv = state.activeConversationId === convId

    // Update lastMessageTimestamp for reconnect gap-fill
    if (!state.lastMessageTimestamp || incoming.created_at > state.lastMessageTimestamp) {
      set({ lastMessageTimestamp: incoming.created_at })
    }

    // Update conversation list preview
    const existingConv = state.conversations.find((c) => c.id === convId)
    if (existingConv) {
      set({
        conversations: sortConversationsByActivity(
          state.conversations.map((c) =>
            c.id === convId
              ? {
                  ...c,
                  last_message_body: incoming.body,
                  last_message_sender_id: incoming.sender_id,
                  last_message_at: incoming.created_at,
                  unread_count: c.unread_count + (incoming.sender_id !== currentUserId ? 1 : 0),
                }
              : c,
          ),
        ),
      })
    } else {
      // 新会话出现时先刷新列表，再按消息所属会话精确提升当前草稿窗口。
      void get()
        .fetchConversations()
        .then(() => get().promoteActivePeerConversation(incoming.conversation_id))
      return
    }

    // Append to messages only when this conversation is active
    if (!isActiveConv) return

    const msgs = get().messages

    // Dedup: skip if this message id already exists (e.g. delivered via REST first)
    if (msgs.some((m) => m.id === incoming.id)) return

    // For self-sent: WS may arrive before REST resolves — use the echoed temp id for exact replacement.
    if (incoming.sender_id === currentUserId && incoming._tempId) {
      const pendingIdx = msgs.findIndex(
        (m) => m._status === 'pending' && m._tempId === incoming._tempId,
      )
      if (pendingIdx !== -1) {
        const newMsgs = [...msgs]
        newMsgs[pendingIdx] = incoming
        set({ messages: newMsgs })
        return
      }
    }

    set({ messages: [...msgs, incoming] })
  },

  handleConversationUpdated: (payload: { conversation_id: number; last_read_at: string }) => {
    set((s) => ({
      conversations: s.conversations.map((c) =>
        c.id === payload.conversation_id ? { ...c, unread_count: 0 } : c,
      ),
    }))
  },

  handleTypingStart: (conversationId: number) => {
    const existing = typingTimeouts.get(conversationId)
    if (existing) clearTimeout(existing)

    set((s) => ({ typingConversationIds: new Set([...s.typingConversationIds, conversationId]) }))

    const timeout = setTimeout(() => {
      set((s) => {
        const next = new Set(s.typingConversationIds)
        next.delete(conversationId)
        return { typingConversationIds: next }
      })
      typingTimeouts.delete(conversationId)
    }, 4000)

    typingTimeouts.set(conversationId, timeout)
  },

  handleTypingStop: (conversationId: number) => {
    const existing = typingTimeouts.get(conversationId)
    if (existing) clearTimeout(existing)
    typingTimeouts.delete(conversationId)

    set((s) => {
      const next = new Set(s.typingConversationIds)
      next.delete(conversationId)
      return { typingConversationIds: next }
    })
  },

  promoteActivePeerConversation: async (conversationId?: number) => {
    const target = findDraftConversation(get(), conversationId)
    if (!target) return false

    await get().selectConversation(target.id)
    return true
  },

  refetchMissedMessages: async () => {
    const { activeConversationId } = get()
    if (!activeConversationId) return

    const requestConvId = activeConversationId

    // Find the last confirmed (non-pending) message ID as the cursor
    const confirmedMessages = get().messages.filter((m) => typeof m.id === 'number')
    const lastId = confirmedMessages.length > 0
      ? Math.max(...confirmedMessages.map((m) => m.id as number))
      : null

    try {
      if (lastId !== null) {
        // Cursor-based gap fill: page forward from lastId until the server returns < 50
        let afterCursor = lastId
        for (let page = 0; page < GAP_FILL_MAX_PAGES; page += 1) {
          const data = await apiFetch<Message[]>(
            `/conversations/${requestConvId}/messages?after=${afterCursor}`
          )
          const state = get()
          if (state.activeConversationId !== requestConvId) return

          if (data.length > 0) {
            const existingIds = new Set(state.messages.map((m) => String(m.id)))
            const newMessages = data
              .map(normalizeIncomingMessage)
              .filter((m) => !existingIds.has(String(m.id)))
            if (newMessages.length > 0) {
              // data is already ASC from the server
              const newest = newMessages[newMessages.length - 1]
              const nextCursor = newest.id as number
              set({
                messages: [...state.messages, ...newMessages],
                lastMessageTimestamp: newest.created_at > (state.lastMessageTimestamp ?? '')
                  ? newest.created_at
                  : state.lastMessageTimestamp,
              })
              if (nextCursor <= afterCursor) break
              afterCursor = nextCursor
            } else if (data.length === MESSAGE_PAGE_SIZE) {
              // after 游标没有推进却还在满页返回，继续请求只会原地打转。
              break
            }
          }

          if (data.length < MESSAGE_PAGE_SIZE) break
        }
      } else {
        // No confirmed messages — fall back to fetching the latest page
        const data = await apiFetch<Message[]>(`/conversations/${requestConvId}/messages`)
        const state = get()
        if (state.activeConversationId !== requestConvId) return

        const reversed = [...data].reverse().map(normalizeIncomingMessage)
        const existingIds = new Set(state.messages.map((m) => String(m.id)))
        const newMessages = reversed.filter((m) => !existingIds.has(String(m.id)))
        if (newMessages.length > 0) {
          set({ messages: [...state.messages, ...newMessages] })
        }
      }
    } catch {
      // ignore
    }
  },
}))

if (import.meta.env.DEV && typeof window !== 'undefined') {
  // 仅在开发 / E2E 环境暴露 store，方便测试读取真实运行态，不影响生产包逻辑。
  ;(window as Window & { __echoChatStore?: typeof useChatStore }).__echoChatStore = useChatStore
}
