import { create } from 'zustand'
import { apiFetch } from '@/lib/api'

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

  fetchConversations: () => Promise<void>
  selectConversation: (convId: number) => Promise<void>
  selectPeer: (peer: PeerInfo) => void
  loadOlderMessages: () => Promise<void>
  sendMessage: (recipientId: number, body: string) => Promise<void>
  retryMessage: (tempId: string, recipientId: number, body: string) => void
  markRead: (convId: number) => Promise<void>
  clearChat: () => void
}

let abortController: AbortController | null = null

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
  const hasTempMessage = messages.some((message) => message._tempId === tempId)
  if (hasTempMessage) {
    return messages.map((message) =>
      message._tempId === tempId ? { ...result } : message,
    )
  }

  if (messages.some((message) => message.id === result.id)) {
    return messages
  }

  return [...messages, result]
}

export const useChatStore = create<ChatState>((set, get) => ({
  conversations: [],
  conversationsLoading: false,
  activeConversationId: null,
  activePeer: null,
  messages: [],
  messagesLoading: false,
  hasMore: false,

  fetchConversations: async () => {
    set({ conversationsLoading: true })
    try {
      const data = await apiFetch<Conversation[]>('/conversations')
      set({ conversations: data, conversationsLoading: false })
    } catch {
      set({ conversationsLoading: false })
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
      set({ messages: [...data].reverse(), messagesLoading: false, hasMore: data.length === 50 })
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

    const older = [...data].reverse()
    set({ messages: [...older, ...state.messages], hasMore: data.length === 50 })
  },

  sendMessage: async (recipientId: number, body: string) => {
    const tempId = `pending-${Date.now()}`
    const { user } = await import('@/stores/auth').then((m) => ({ user: m.useAuthStore.getState().user }))
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
      const result = await apiFetch<Message>('/messages', {
        method: 'POST',
        body: JSON.stringify({ recipient_id: recipientId, body }),
      })
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
}))
