import { useEffect, useRef } from 'react'
import { toast } from 'sonner'
import i18n from '@/lib/i18n'
import { useChatStore, type Message } from '@/stores/chat'
import { usePresenceStore } from '@/stores/presence'
import { useFriendRequestStore, type FriendRequest } from '@/stores/friendRequests'
import { useAuthStore } from '@/stores/auth'
import { setWsConnected } from '@/lib/wsConnection'

// Module-level socket reference so sendWsMessage can be called from anywhere
let globalWs: WebSocket | null = null

export function sendWsMessage(data: object) {
  if (globalWs?.readyState === WebSocket.OPEN) {
    globalWs.send(JSON.stringify(data))
  }
}

type WsEvent =
  | { type: 'message.new'; payload: Message }
  | { type: 'conversation.updated'; payload: { conversation_id: number; last_read_message_id: number } }
  | { type: 'typing.start'; payload: { conversation_id: number; user_id: number } }
  | { type: 'typing.stop'; payload: { conversation_id: number; user_id: number } }
  | { type: 'presence.online'; payload: { user_id: number } }
  | { type: 'presence.offline'; payload: { user_id: number } }
  | { type: 'friend_request.new'; payload: FriendRequest }
  | { type: 'friend_request.accepted'; payload: FriendRequest }
  | { type: 'friend_request.declined'; payload: FriendRequest }

function handleWsEvent(event: WsEvent) {
  const chat = useChatStore.getState()
  const presence = usePresenceStore.getState()
  const friendReqs = useFriendRequestStore.getState()
  const currentUserId = useAuthStore.getState().user?.id

  switch (event.type) {
    case 'message.new':
      chat.handleIncomingMessage(event.payload)
      break
    case 'conversation.updated':
      chat.handleConversationUpdated(event.payload)
      break
    case 'typing.start':
      chat.handleTypingStart(event.payload.conversation_id)
      break
    case 'typing.stop':
      chat.handleTypingStop(event.payload.conversation_id)
      break
    case 'presence.online':
      presence.setOnline(event.payload.user_id)
      break
    case 'presence.offline':
      presence.setOffline(event.payload.user_id)
      break
    case 'friend_request.new':
      if (event.payload.sender_id === currentUserId) {
        friendReqs.addSent(event.payload)
      } else {
        friendReqs.addIncoming(event.payload)
        const name = event.payload.display_name || event.payload.username
        toast.info(i18n.t('ws.friendRequestReceived', { name }))
      }
      break
    case 'friend_request.accepted': {
      const direction = event.payload.sender_id === currentUserId ? 'sent' : 'received'
      friendReqs.handleAccepted(event.payload, direction)
      // 只给非操作方（收到对方接受通知的一侧）显示 toast
      if (direction === 'sent') {
        const name = event.payload.display_name || event.payload.username
        toast.success(i18n.t('ws.friendRequestAccepted', { name }))
      }
      break
    }
    case 'friend_request.declined':
      friendReqs.handleDeclined(
        event.payload,
        event.payload.sender_id === currentUserId ? 'sent' : 'received',
      )
      break
  }
}

export function useWebSocket() {
  const reconnectDelayRef = useRef(1000)
  const isFirstConnectionRef = useRef(true)

  useEffect(() => {
    let destroyed = false
    let ws: WebSocket | null = null
    let reconnectTimer: ReturnType<typeof setTimeout> | null = null

    const connect = () => {
      if (destroyed) return
      if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
        return
      }

      const token = localStorage.getItem('token')
      if (!token) return

      const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:'
      ws = new WebSocket(`${protocol}//${location.host}/ws?token=${token}`)
      globalWs = ws

      ws.onopen = () => {
        setWsConnected(true)
        reconnectDelayRef.current = 1000

        if (!isFirstConnectionRef.current) {
          // Clear stale presence state — server will re-send a snapshot of online friends
          usePresenceStore.getState().clearAll()
          // 重连后先刷新会话列表：草稿聊天可能已经在离线期间变成正式会话。
          void useChatStore
            .getState()
            .fetchConversations()
            .then(async () => {
              const promoted = await useChatStore.getState().promoteActivePeerConversation()
              if (!promoted) {
                await useChatStore.getState().refetchMissedMessages()
              }
            })
          // 补回离线期间漏掉的好友申请事件
          void useFriendRequestStore.getState().fetchAll()
        }
        isFirstConnectionRef.current = false
      }

      ws.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data as string) as WsEvent
          handleWsEvent(msg)
        } catch {
          // ignore malformed messages
        }
      }

      ws.onclose = () => {
        setWsConnected(false)
        if (globalWs === ws) globalWs = null
        if (destroyed) return

        ws = null
        if (reconnectTimer) clearTimeout(reconnectTimer)
        const delay = reconnectDelayRef.current
        // 即使浏览器没及时派发 online 事件，聊天场景下也别让退避拖到半分钟那么久。
        reconnectDelayRef.current = Math.min(delay * 2, 5000)
        reconnectTimer = setTimeout(connect, delay)
      }

      ws.onerror = () => {
        // ws.onclose fires after onerror and handles reconnect
      }
    }

    const reconnectImmediately = () => {
      if (destroyed) return

      // 浏览器网络恢复后，别再傻等指数退避定时器，立刻抢一次重连。
      if (reconnectTimer) {
        clearTimeout(reconnectTimer)
        reconnectTimer = null
      }
      reconnectDelayRef.current = 1000
      connect()
    }

    const closeSocketWhenOffline = () => {
      if (destroyed) return

      // 某些环境下切到离线不会立刻触发 ws.onclose，主动关闭能让重连状态机更可预期。
      if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
        ws.close()
      }
    }

    connect()
    window.addEventListener('online', reconnectImmediately)
    window.addEventListener('offline', closeSocketWhenOffline)

    return () => {
      destroyed = true
      setWsConnected(false)
      window.removeEventListener('online', reconnectImmediately)
      window.removeEventListener('offline', closeSocketWhenOffline)
      if (reconnectTimer) clearTimeout(reconnectTimer)
      ws?.close()
      if (globalWs === ws) globalWs = null
    }
  }, [])
}
