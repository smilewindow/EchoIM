import { useEffect, useRef, useCallback, useState } from 'react'
import { Send, ArrowLeft, AlertCircle, RefreshCw, MessageSquare } from 'lucide-react'
import { useChatStore, type Message } from '@/stores/chat'
import { useAuthStore } from '@/stores/auth'

/* ── Helpers ── */

function formatTime(dateStr: string): string {
  const d = new Date(dateStr)
  return d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false })
}

function formatDateGroup(dateStr: string): string {
  const d = new Date(dateStr)
  const now = new Date()
  if (isSameDay(d, now)) return 'Today'
  const yesterday = new Date(now)
  yesterday.setDate(yesterday.getDate() - 1)
  if (isSameDay(d, yesterday)) return 'Yesterday'
  return d.toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' })
}

function isSameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  )
}

function initials(displayName: string | null | undefined, username: string): string {
  const name = displayName || username
  return name.slice(0, 2).toUpperCase()
}

/* ── Types ── */

interface Props {
  onBack?: () => void
}

/* ── Component ── */

export function ChatView({ onBack }: Props) {
  const {
    activeConversationId,
    activePeer,
    conversations,
    messages,
    messagesLoading,
    hasMore,
    sendMessage,
    retryMessage,
    loadOlderMessages,
    markRead,
  } = useChatStore()

  const { user } = useAuthStore()

  const messagesEndRef = useRef<HTMLDivElement>(null)
  const messagesContainerRef = useRef<HTMLDivElement>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const [body, setBody] = useState('')
  const [loadingOlder, setLoadingOlder] = useState(false)
  const prevMessagesLengthRef = useRef(0)

  // Resolve peer info
  const conv = activeConversationId
    ? conversations.find((c) => c.id === activeConversationId)
    : null

  const peer = conv
    ? {
        id: conv.peer_id,
        username: conv.peer_username,
        display_name: conv.peer_display_name,
        avatar_url: conv.peer_avatar_url,
      }
    : activePeer

  const recipientId = peer?.id ?? 0

  // Scroll to bottom when new messages arrive (only if near bottom)
  useEffect(() => {
    const container = messagesContainerRef.current
    if (!container || messagesLoading) return

    const isNearBottom =
      container.scrollTop + container.clientHeight >= container.scrollHeight - 120
    const isInitialLoad = prevMessagesLengthRef.current === 0 && messages.length > 0

    if (isInitialLoad) {
      // Instant scroll on initial load
      messagesEndRef.current?.scrollIntoView()
    } else if (isNearBottom) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
    }

    prevMessagesLengthRef.current = messages.length
  }, [messages.length, messagesLoading])

  // Reset scroll ref when conversation changes
  useEffect(() => {
    prevMessagesLengthRef.current = 0
  }, [activeConversationId, activePeer])

  // Mark read after messages finish loading (covers initial open + Phase 10 new messages via WS)
  useEffect(() => {
    if (activeConversationId && !messagesLoading && messages.length > 0) {
      markRead(activeConversationId)
    }
  }, [activeConversationId, messagesLoading, messages.length, markRead])

  // Mark read again when tab regains focus
  useEffect(() => {
    const handleVisibility = () => {
      if (document.visibilityState === 'visible' && activeConversationId) {
        markRead(activeConversationId)
      }
    }
    document.addEventListener('visibilitychange', handleVisibility)
    return () => document.removeEventListener('visibilitychange', handleVisibility)
  }, [activeConversationId, markRead])

  // Auto-grow textarea
  const handleInput = useCallback(() => {
    const el = textareaRef.current
    if (!el) return
    el.style.height = 'auto'
    el.style.height = el.scrollHeight + 'px'
  }, [])

  const handleSend = useCallback(() => {
    const trimmed = body.trim()
    if (!trimmed || !recipientId) return
    sendMessage(recipientId, trimmed)
    setBody('')
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto'
    }
  }, [body, recipientId, sendMessage])

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault()
        handleSend()
      }
    },
    [handleSend],
  )

  const handleLoadOlder = useCallback(async () => {
    setLoadingOlder(true)
    // Preserve scroll position
    const container = messagesContainerRef.current
    const prevHeight = container?.scrollHeight ?? 0

    try {
      await loadOlderMessages()
      // After render, restore scroll position
      requestAnimationFrame(() => {
        if (container) {
          container.scrollTop += container.scrollHeight - prevHeight
        }
        setLoadingOlder(false)
      })
    } catch {
      setLoadingOlder(false)
    }
  }, [loadOlderMessages])

  // Build message groups with date dividers
  const renderMessages = () => {
    if (messagesLoading) {
      return (
        <div style={{ display: 'flex', justifyContent: 'center', padding: '40px 0' }}>
          <div className="echo-spinner" />
        </div>
      )
    }

    if (messages.length === 0) {
      return (
        <div className="echo-chat-empty">
          <MessageSquare
            size={36}
            className="echo-chat-empty-icon"
            strokeWidth={1.5}
          />
          <p className="echo-chat-empty-text">No messages yet</p>
          <p className="echo-chat-empty-hint">Say something to get started</p>
        </div>
      )
    }

    const elements: React.ReactNode[] = []
    let lastDate = ''
    let lastSenderId: number | string | null = null

    messages.forEach((msg, i) => {
      const dateGroup = formatDateGroup(msg.created_at)
      if (dateGroup !== lastDate) {
        elements.push(
          <div key={`date-${i}`} className="echo-date-divider">
            {dateGroup}
          </div>,
        )
        lastDate = dateGroup
      }

      const isSelf = msg.sender_id === user?.id
      const isGroupStart = lastSenderId !== msg.sender_id
      lastSenderId = msg.sender_id

      elements.push(
        <MessageBubble
          key={String(msg.id)}
          msg={msg}
          isSelf={isSelf}
          isGroupStart={isGroupStart}
          recipientId={recipientId}
          retryMessage={retryMessage}
        />,
      )
    })

    return elements
  }

  if (!peer) return null

  return (
    <div className="echo-chat">
      {/* Header */}
      <div className="echo-chat-header">
        <button className="echo-chat-back-btn" onClick={onBack} aria-label="Go back">
          <ArrowLeft size={18} />
        </button>

        <div className="echo-avatar-wrap">
          <div className="echo-avatar" title={peer.display_name || peer.username}>
            {peer.avatar_url ? (
              <img src={peer.avatar_url} alt="" className="echo-avatar-img" />
            ) : (
              <span className="echo-avatar-initials">
                {initials(peer.display_name, peer.username)}
              </span>
            )}
          </div>
        </div>

        <div style={{ flex: 1, minWidth: 0 }}>
          <p className="echo-chat-peer-name">{peer.display_name || peer.username}</p>
          {peer.display_name && (
            <p className="echo-chat-peer-handle">@{peer.username}</p>
          )}
        </div>
      </div>

      {/* Messages */}
      <div className="echo-chat-messages echo-scroll" ref={messagesContainerRef}>
        {hasMore && (
          <div className="echo-chat-load-more">
            <button
              className="echo-load-more-btn"
              onClick={handleLoadOlder}
              disabled={loadingOlder}
            >
              {loadingOlder ? 'Loading…' : 'Load older messages'}
            </button>
          </div>
        )}

        {renderMessages()}

        <div ref={messagesEndRef} />
      </div>

      {/* Input */}
      <div className="echo-message-input-wrap">
        <div className="echo-message-textarea-wrap">
          <textarea
            ref={textareaRef}
            className="echo-message-textarea"
            placeholder="Message…"
            rows={1}
            value={body}
            onChange={(e) => setBody(e.target.value)}
            onInput={handleInput}
            onKeyDown={handleKeyDown}
          />
        </div>
        <button
          className="echo-message-send-btn"
          onClick={handleSend}
          disabled={!body.trim()}
          aria-label="Send message"
        >
          <Send size={18} />
        </button>
      </div>
    </div>
  )
}

/* ── MessageBubble sub-component ── */

interface BubbleProps {
  msg: Message
  isSelf: boolean
  isGroupStart: boolean
  recipientId: number
  retryMessage: (tempId: string, recipientId: number, body: string) => void
}

function MessageBubble({ msg, isSelf, isGroupStart, recipientId, retryMessage }: BubbleProps) {
  const isPending = msg._status === 'pending'
  const isFailed = msg._status === 'failed'

  const rowClass = [
    'echo-bubble-row',
    isSelf ? 'echo-bubble-row--self' : 'echo-bubble-row--other',
    isGroupStart ? 'echo-bubble-row--group-start' : '',
  ]
    .filter(Boolean)
    .join(' ')

  const bubbleClass = [
    'echo-bubble',
    isSelf ? 'echo-bubble--self' : 'echo-bubble--other',
    isPending ? 'echo-bubble--pending' : '',
    isFailed ? 'echo-bubble--failed' : '',
  ]
    .filter(Boolean)
    .join(' ')

  return (
    <div className={rowClass}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: isSelf ? 'flex-end' : 'flex-start', maxWidth: '70%', minWidth: 0 }}>
        <div className={bubbleClass}>
          <p className="echo-bubble-body">{msg.body}</p>
          <div className="echo-bubble-footer">
            <span className="echo-bubble-time">{formatTime(msg.created_at)}</span>
            {isPending && (
              <span className="echo-bubble-status">
                <div className="echo-spinner" style={{ width: 12, height: 12, borderWidth: 1.5 }} />
              </span>
            )}
            {isFailed && (
              <span className="echo-bubble-status">
                <AlertCircle size={12} style={{ color: 'rgba(255, 80, 80, 0.7)' }} />
              </span>
            )}
          </div>
        </div>
        {isFailed && msg._tempId && (
          <button
            className="echo-retry-btn"
            onClick={() => retryMessage(msg._tempId!, recipientId, msg.body)}
          >
            <RefreshCw size={11} />
            Retry
          </button>
        )}
      </div>
    </div>
  )
}
