import { create } from 'zustand'
import { toast } from 'sonner'
import { apiFetch, uploadImageBlob } from '@/lib/api'
import { compressImage, validateImageFile } from '@/lib/image'
import i18n from '@/lib/i18n'
import { useAuthStore } from '@/stores/auth'
import { isWsConnected } from '@/lib/wsConnection'

export interface Conversation {
  id: number
  created_at: string
  last_read_message_id: number | null
  unread_count: number
  last_message_body: string | null
  last_message_type?: string
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
  body: string | null
  created_at: string
  client_temp_id?: string
  message_type?: 'text' | 'image'
  media_url?: string | null
  _status?: 'pending' | 'failed'
  _tempId?: string
  _localMediaUrl?: string
  _localBlob?: Blob
  _uploadStage?: 'uploading' | 'sending'
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
  sendMessage: (recipientId: number, body: string) => boolean
  retryMessage: (tempId: string) => void
  sendImageMessage: (recipientId: number, file: File) => Promise<void>
  markRead: (convId: number, lastReadMessageId: number) => Promise<void>
  clearChat: () => void
  handleIncomingMessage: (message: Message) => void
  handleConversationUpdated: (payload: { conversation_id: number; last_read_message_id: number }) => void
  handleTypingStart: (conversationId: number) => void
  handleTypingStop: (conversationId: number) => void
  promoteActivePeerConversation: (conversationId?: number) => Promise<boolean>
  refetchMissedMessages: () => Promise<void>
}

let abortController: AbortController | null = null

// Typing auto-clear timeouts keyed by conversation_id (outside Zustand to avoid serialization issues)
const typingTimeouts = new Map<number, ReturnType<typeof setTimeout>>()
const pendingReadMessageIds = new Map<number, number>()
const MESSAGE_PAGE_SIZE = 50
const GAP_FILL_MAX_PAGES = 20
let tempMessageSeq = 0

function createTempMessageId() {
  // tempId 只需要在当前客户端会话里唯一，用来对账 optimistic message 和服务端回包。
  tempMessageSeq += 1
  return `pending-${Date.now()}-${tempMessageSeq}`
}

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

function syncPendingReadAcks(conversations: Conversation[]) {
  conversations.forEach((conversation) => {
    const pendingMessageId = pendingReadMessageIds.get(conversation.id)
    if (pendingMessageId === undefined) return

    if ((conversation.last_read_message_id ?? 0) >= pendingMessageId) {
      pendingReadMessageIds.delete(conversation.id)
    }
  })
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
  conversationsLoading: true,
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
      syncPendingReadAcks(data)
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

  sendMessage: (recipientId: number, body: string) => {
    const { user } = useAuthStore.getState()
    if (!user) {
      console.error('prepare sendMessage failed: missing authenticated user')
      toast.error(i18n.t('chat.sendFailed'))
      return false
    }

    let tempId = ''
    let requestConversationId: number | null = null
    let requestPeerId: number | null = null
    let wasNewConversation = false

    try {
      tempId = createTempMessageId()
      const initialState = get()
      requestConversationId = initialState.activeConversationId
      requestPeerId = initialState.activePeer?.id ?? null
      wasNewConversation = requestConversationId === null

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
    } catch (err) {
      // 发送前的本地准备失败时，保留输入内容，不插入失败气泡，用户可以直接重试。
      console.error('prepare sendMessage failed', err)
      toast.error(i18n.t('chat.sendFailed'))
      return false
    }

    void (async () => {
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
          void get().fetchConversations()
        }
      } catch (err) {
        console.error('request sendMessage failed', err)
        const state = get()

        if (!isSameChatContext(state, requestConversationId, requestPeerId)) {
          return
        }

        set({
          messages: state.messages.map((message) =>
            message._tempId === tempId ? { ...message, _status: 'failed' } : message,
          ),
        })
        toast.error(i18n.t('chat.sendFailed'))
      }
    })()

    return true
  },

  retryMessage: (tempId: string) => {
    const state = get()
    const msg = state.messages.find((m) => m._tempId === tempId)
    if (!msg) return

    const recipientId =
      state.activePeer?.id ??
      state.conversations.find((c) => c.id === state.activeConversationId)?.peer_id ??
      0
    if (!recipientId) return

    // 立即翻转为 pending — 移除重试按钮，防止重复点击
    set({
      messages: get().messages.map((m) =>
        m._tempId === tempId ? { ...m, _status: 'pending' } : m,
      ),
    })

    if (msg.message_type !== 'image') {
      // 文字消息重试：删除失败气泡，重新发送
      set({ messages: get().messages.filter((m) => m._tempId !== tempId) })
      if (msg.body) get().sendMessage(recipientId, msg.body)
      return
    }

    // 图片消息重试
    void (async () => {
      let mediaUrl = msg.media_url ?? null

      // 阶段 1：如果还没有上传成功的 URL，重新上传
      if (msg._uploadStage === 'uploading' && msg._localBlob) {
        mediaUrl = await uploadImageBlob(msg._localBlob)
        if (!mediaUrl) {
          set({
            messages: get().messages.map((m) =>
              m._tempId === tempId
                ? { ...m, _status: 'failed', _uploadStage: 'uploading' }
                : m,
            ),
          })
          return
        }
        set({
          messages: get().messages.map((m) =>
            m._tempId === tempId
              ? { ...m, _uploadStage: 'sending', media_url: mediaUrl }
              : m,
          ),
        })
      }

      if (!mediaUrl) return

      // 阶段 2：发送消息
      try {
        const result = normalizeIncomingMessage(
          await apiFetch<Message>('/messages', {
            method: 'POST',
            body: JSON.stringify({
              recipient_id: recipientId,
              message_type: 'image',
              media_url: mediaUrl,
              client_temp_id: tempId,
            }),
          }),
        )
        const currentState = get()
        const localMediaUrl = currentState.messages.find((m) => m._tempId === tempId)?._localMediaUrl
        if (
          isSameChatContext(
            currentState,
            msg.conversation_id === -1 ? null : msg.conversation_id,
            recipientId,
          )
        ) {
          const wasNewConv = msg.conversation_id === -1
          set({
            messages: replaceOrAppendMessage(currentState.messages, tempId, result),
            activeConversationId: wasNewConv ? result.conversation_id : currentState.activeConversationId,
            activePeer: wasNewConv ? null : currentState.activePeer,
          })
        }
        if (localMediaUrl) URL.revokeObjectURL(localMediaUrl)
        // 更新会话列表预览
        const convId = result.conversation_id
        const convState = get()
        const existing = convState.conversations.find((c) => c.id === convId)
        if (existing) {
          set({
            conversations: sortConversationsByActivity(
              convState.conversations.map((c) =>
                c.id === convId
                  ? {
                      ...c,
                      last_message_body: result.body,
                      last_message_type: result.message_type,
                      last_message_at: result.created_at,
                      last_message_sender_id: result.sender_id,
                    }
                  : c,
              ),
            ),
          })
        } else if (msg.conversation_id === -1) {
          // New conversation created via retry — fetch full list to get peer info
          void get().fetchConversations()
        }
      } catch {
        set({
          messages: get().messages.map((m) =>
            m._tempId === tempId
              ? { ...m, _status: 'failed', _uploadStage: 'sending' }
              : m,
          ),
        })
      }
    })()
  },

  sendImageMessage: async (recipientId: number, file: File) => {
    const { user } = useAuthStore.getState()
    if (!user) {
      toast.error(i18n.t('chat.sendFailed'))
      return
    }

    // 1. 校验并压缩
    const validationError = validateImageFile(file)
    if (validationError) {
      if (validationError === 'INVALID_TYPE') {
        toast.error(i18n.t('profile.invalidFileType'))
      } else {
        toast.error(i18n.t('profile.fileTooLarge'))
      }
      return
    }

    // Capture context before any async operation — prevents race condition
    // if user switches conversations during compression
    const initialState = get()
    const requestConversationId = initialState.activeConversationId
    const requestPeerId = initialState.activePeer?.id ?? null
    const wasNewConversation = requestConversationId === null

    let blob: Blob
    try {
      blob = await compressImage(file, { maxDimension: 1600, targetSizeBytes: 2 * 1024 * 1024, minDimension: 400 })
    } catch {
      toast.error(i18n.t('chat.sendFailed'))
      return
    }

    // 2. 创建本地 blob URL
    const objectUrl = URL.createObjectURL(blob)
    const tempId = createTempMessageId()

    // 3. 插入乐观气泡
    const optimistic: Message = {
      id: tempId,
      conversation_id: requestConversationId ?? -1,
      sender_id: user.id,
      body: null,
      created_at: new Date().toISOString(),
      message_type: 'image',
      _status: 'pending',
      _uploadStage: 'uploading',
      _localMediaUrl: objectUrl,
      _localBlob: blob,
      _tempId: tempId,
    }
    set({ messages: [...initialState.messages, optimistic] })

    // 4. 上传图片
    const mediaUrl = await uploadImageBlob(blob)
    if (!mediaUrl) {
      set({
        messages: get().messages.map((m) =>
          m._tempId === tempId
            ? { ...m, _status: 'failed', _uploadStage: 'uploading' }
            : m,
        ),
      })
      toast.error(i18n.t('chat.sendFailed'))
      return
    }

    // 更新气泡进入 sending 阶段
    set({
      messages: get().messages.map((m) =>
        m._tempId === tempId
          ? { ...m, _uploadStage: 'sending', media_url: mediaUrl }
          : m,
      ),
    })

    // 5. 发送消息
    try {
      const result = normalizeIncomingMessage(
        await apiFetch<Message>('/messages', {
          method: 'POST',
          body: JSON.stringify({
            recipient_id: recipientId,
            message_type: 'image',
            media_url: mediaUrl,
            client_temp_id: tempId,
          }),
        }),
      )

      const state = get()
      const shouldUpdateActiveMessages = isSameChatContext(
        state,
        requestConversationId,
        requestPeerId,
      )

      if (shouldUpdateActiveMessages) {
        set({
          messages: replaceOrAppendMessage(state.messages, tempId, result),
          activeConversationId: wasNewConversation
            ? result.conversation_id
            : state.activeConversationId,
          activePeer: wasNewConversation ? null : state.activePeer,
        })
      }
      URL.revokeObjectURL(objectUrl)

      // 更新会话列表预览
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
                    last_message_type: result.message_type,
                    last_message_at: result.created_at,
                    last_message_sender_id: result.sender_id,
                  }
                : c,
            ),
          ),
        })
      } else if (wasNewConversation) {
        void get().fetchConversations()
      }
    } catch {
      set({
        messages: get().messages.map((m) =>
          m._tempId === tempId
            ? { ...m, _status: 'failed', _uploadStage: 'sending' }
            : m,
        ),
      })
      toast.error(i18n.t('chat.sendFailed'))
    }
  },

  markRead: async (convId: number, lastReadMessageId: number) => {
    const pendingMessageId = pendingReadMessageIds.get(convId) ?? 0
    if (pendingMessageId >= lastReadMessageId) return

    pendingReadMessageIds.set(convId, lastReadMessageId)

    try {
      await apiFetch(`/conversations/${convId}/read`, {
        method: 'PUT',
        body: JSON.stringify({ last_read_message_id: lastReadMessageId }),
      })

      // WS 在线时等服务端广播确认；离线时主动回拉一次服务端真相，避免列表一直卡在旧未读数。
      if (!isWsConnected()) {
        await get().fetchConversations()
      }
    } catch (err) {
      console.error('markRead failed:', err)
      if (pendingReadMessageIds.get(convId) === lastReadMessageId) {
        pendingReadMessageIds.delete(convId)
      }
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
                  last_message_type: incoming.message_type,
                  last_message_sender_id: incoming.sender_id,
                  last_message_at: incoming.created_at,
                  // 只把真正越过已读游标的对方消息计入未读，避免旧回执把边界冲回去。
                  unread_count: c.unread_count + (
                    incoming.sender_id !== currentUserId &&
                    typeof incoming.id === 'number' &&
                    incoming.id > (c.last_read_message_id ?? 0)
                      ? 1
                      : 0
                  ),
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

  handleConversationUpdated: (payload: { conversation_id: number; last_read_message_id: number }) => {
    const state = get()
    const currentUserId = useAuthStore.getState().user?.id
    const currentConversation = state.conversations.find((conversation) => conversation.id === payload.conversation_id)

    if (!currentConversation) return
    if (payload.last_read_message_id < (currentConversation.last_read_message_id ?? 0)) return

    let earliestLoadedMessageId: number | null = null
    let unreadCount = 0
    for (const message of state.messages) {
      if (typeof message.id !== 'number') continue
      const msgId = message.id as number
      if (earliestLoadedMessageId === null || msgId < earliestLoadedMessageId) {
        earliestLoadedMessageId = msgId
      }
      if (message.sender_id !== currentUserId && msgId > payload.last_read_message_id) {
        unreadCount++
      }
    }
    const canRecomputeActiveUnread =
      state.activeConversationId === payload.conversation_id &&
      earliestLoadedMessageId !== null &&
      payload.last_read_message_id >= earliestLoadedMessageId

    const nextConversations = state.conversations.map((conversation) => {
      if (conversation.id !== payload.conversation_id) return conversation
      return canRecomputeActiveUnread
        ? { ...conversation, last_read_message_id: payload.last_read_message_id, unread_count: unreadCount }
        : { ...conversation, last_read_message_id: payload.last_read_message_id }
    })

    syncPendingReadAcks(nextConversations)
    set({ conversations: nextConversations })

    if (!canRecomputeActiveUnread) {
      void get().fetchConversations()
    }
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
    const lastId = get().messages.reduce<number | null>((max, m) => {
      if (typeof m.id !== 'number') return max
      const id = m.id as number
      return max === null ? id : Math.max(max, id)
    }, null)

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
