/* eslint-disable react-hooks/preserve-manual-memoization */
import { useEffect, useLayoutEffect, useRef, useCallback, useState } from 'react'
import { Send, ArrowLeft, AlertCircle, RefreshCw, MessageSquare, ChevronDown } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { useChatStore, type Message } from '@/stores/chat'
import { useAuthStore } from '@/stores/auth'
import { usePresenceStore } from '@/stores/presence'
import { sendWsMessage } from '@/hooks/useWebSocket'

/* ── Helpers ── */

const NEAR_BOTTOM_THRESHOLD_PX = 120
const NEW_MESSAGE_ALERT_GAP_PX = 12
const DEFAULT_CHAT_FOOTER_HEIGHT_PX = 72
const SKELETON_BUBBLE_WIDTHS = [40, 55, 30, 60, 35, 50, 45, 65]


function useFormatDateGroup() {
  const { t, i18n } = useTranslation()

  return (dateStr: string): string => {
    const d = new Date(dateStr)
    const now = new Date()
    if (isSameDay(d, now)) return t('chat.today')
    const yesterday = new Date(now)
    yesterday.setDate(yesterday.getDate() - 1)
    if (isSameDay(d, yesterday)) return t('common.yesterday')
    return d.toLocaleDateString(i18n.resolvedLanguage, {
      weekday: 'long',
      month: 'short',
      day: 'numeric',
    })
  }
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

function isNearBottom(container: HTMLDivElement): boolean {
  return container.scrollTop + container.clientHeight >= container.scrollHeight - NEAR_BOTTOM_THRESHOLD_PX
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
    typingConversationIds,
    sendMessage,
    retryMessage,
    loadOlderMessages,
    markRead,
  } = useChatStore()

  const { user } = useAuthStore()
  const { t } = useTranslation()
  const onlineUsers = usePresenceStore((s) => s.onlineUsers)
  const formatDateGroup = useFormatDateGroup()

  const messagesEndRef = useRef<HTMLDivElement>(null)
  const messagesContainerRef = useRef<HTMLDivElement>(null)
  const footerRef = useRef<HTMLDivElement>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const [body, setBody] = useState('')
  const [loadingOlder, setLoadingOlder] = useState(false)
  const [newMessageAlert, setNewMessageAlert] = useState(false)
  const [footerHeight, setFooterHeight] = useState(DEFAULT_CHAT_FOOTER_HEIGHT_PX)
  const prevMessagesLengthRef = useRef(0)
  const markReadIfVisibleRef = useRef<() => void>(() => {})
  const wasNearBottomRef = useRef(true)

  // Typing send state
  const typingActiveRef = useRef(false)
  const typingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

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
  const activeUnreadCount = conv?.unread_count ?? 0
  const activeLastReadMessageId = conv?.last_read_message_id ?? 0

  const markReadIfVisible = useCallback(() => {
    if (!activeConversationId || activeUnreadCount === 0 || messagesLoading || messages.length === 0) {
      return
    }

    if (document.visibilityState !== 'visible' || !document.hasFocus()) {
      return
    }

    const container = messagesContainerRef.current
    if (!container || !isNearBottom(container)) return

    const latestConfirmedMessage = [...messages]
      .reverse()
      .find((message) => typeof message.id === 'number')

    if (!latestConfirmedMessage) return
    if ((latestConfirmedMessage.id as number) <= activeLastReadMessageId) return

    markRead(activeConversationId, latestConfirmedMessage.id as number)
  }, [
    activeConversationId,
    activeLastReadMessageId,
    activeUnreadCount,
    messages,
    messagesLoading,
    markRead,
  ])

  // Keep markReadIfVisibleRef in sync so scroll effect can call it without stale closure
  useEffect(() => {
    markReadIfVisibleRef.current = markReadIfVisible
  }, [markReadIfVisible])

  // 底部区域高度会随着 typing indicator 和输入框行数变化，alert 需要实时避让。
  useLayoutEffect(() => {
    const footer = footerRef.current
    if (!footer) return

    const updateFooterHeight = () => {
      const h = footer.offsetHeight
      setFooterHeight(prev => prev === h ? prev : h)
    }

    updateFooterHeight()

    const observer = new ResizeObserver(() => {
      updateFooterHeight()
    })

    observer.observe(footer)
    return () => observer.disconnect()
  }, [])

  const scrollToBottom = useCallback((behavior: ScrollBehavior = 'smooth') => {
    wasNearBottomRef.current = true

    requestAnimationFrame(() => {
      setNewMessageAlert(false)
      messagesEndRef.current?.scrollIntoView({ behavior, block: 'end' })

      requestAnimationFrame(() => {
        markReadIfVisibleRef.current()
      })
    })
  }, [])

  // Scroll to bottom when new messages arrive (only if near bottom)
  useEffect(() => {
    const container = messagesContainerRef.current
    if (!container || messagesLoading) return

    const isInitialLoad = prevMessagesLengthRef.current === 0 && messages.length > 0
    const shouldStickToBottom = isInitialLoad || wasNearBottomRef.current

    if (shouldStickToBottom) {
      scrollToBottom(isInitialLoad ? 'auto' : 'smooth')
    }

    prevMessagesLengthRef.current = messages.length
  }, [messages.length, messagesLoading, scrollToBottom])

  // Reset scroll ref when conversation changes
  useEffect(() => {
    prevMessagesLengthRef.current = 0
    wasNearBottomRef.current = true

    const frame = requestAnimationFrame(() => {
      setNewMessageAlert(false)
    })

    return () => cancelAnimationFrame(frame)
  }, [activeConversationId, activePeer])

  // 只要当前不在底部且仍有未读，就保留回到底部入口；分页和自发消息不会污染 unread_count。
  useEffect(() => {
    const frame = requestAnimationFrame(() => {
      setNewMessageAlert(
        Boolean(activeConversationId) &&
          activeUnreadCount > 0 &&
          !wasNearBottomRef.current,
      )
    })

    return () => cancelAnimationFrame(frame)
  }, [activeConversationId, activeUnreadCount])

  // 只有消息真正滚到可见底部时才标记已读，避免用户上翻历史时误清未读。
  useEffect(() => {
    const frame = requestAnimationFrame(() => {
      markReadIfVisible()
    })

    return () => cancelAnimationFrame(frame)
  }, [markReadIfVisible])

  // 切回前台或重新聚焦后，再次检查最新消息是否真的已经进入可视区域。
  useEffect(() => {
    const handleVisibility = () => {
      requestAnimationFrame(() => {
        markReadIfVisible()
      })
    }

    const handleFocus = () => {
      requestAnimationFrame(() => {
        markReadIfVisible()
      })
    }

    document.addEventListener('visibilitychange', handleVisibility)
    window.addEventListener('focus', handleFocus)

    return () => {
      document.removeEventListener('visibilitychange', handleVisibility)
      window.removeEventListener('focus', handleFocus)
    }
  }, [markReadIfVisible])

  useEffect(() => {
    const container = messagesContainerRef.current
    if (!container) return

    const handleScroll = () => {
      const nearBottom = isNearBottom(container)
      wasNearBottomRef.current = nearBottom
      const shouldAlert = !nearBottom && activeUnreadCount > 0
      setNewMessageAlert(prev => prev === shouldAlert ? prev : shouldAlert)
      markReadIfVisible()
    }

    container.addEventListener('scroll', handleScroll, { passive: true })
    return () => container.removeEventListener('scroll', handleScroll)
  }, [activeConversationId, activeUnreadCount, markReadIfVisible])

  const stopTyping = useCallback(() => {
    if (typingTimerRef.current) {
      clearTimeout(typingTimerRef.current)
      typingTimerRef.current = null
    }

    const shouldSendStop = typingActiveRef.current && activeConversationId
    typingActiveRef.current = false

    if (shouldSendStop) {
      sendWsMessage({ type: 'typing.stop', conversation_id: activeConversationId })
    }
  }, [activeConversationId])

  // Stop typing when switching conversations (cleanup captures old conv ID via closure)
  useEffect(() => {
    return () => stopTyping()
  }, [stopTyping])

  const handleTypingInput = useCallback(() => {
    if (!activeConversationId) return

    if (!typingActiveRef.current) {
      typingActiveRef.current = true
      sendWsMessage({ type: 'typing.start', conversation_id: activeConversationId })
    }

    if (typingTimerRef.current) clearTimeout(typingTimerRef.current)
    typingTimerRef.current = setTimeout(() => {
      stopTyping()
    }, 3000)
  }, [activeConversationId, stopTyping])

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

    stopTyping()
    wasNearBottomRef.current = true
    setNewMessageAlert(false)
    sendMessage(recipientId, trimmed)
    scrollToBottom()
    setBody('')
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto'
    }
  }, [body, recipientId, scrollToBottom, sendMessage, stopTyping])

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
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, padding: '24px 16px' }}>
          {SKELETON_BUBBLE_WIDTHS.map((w, i) => {
            const isSelf = i % 3 === 0
            return (
              <div
                key={i}
                style={{
                  display: 'flex',
                  justifyContent: isSelf ? 'flex-end' : 'flex-start',
                }}
              >
                <div
                  className="echo-skeleton"
                  style={{
                    width: `${w}%`,
                    height: 36,
                    borderRadius: 14,
                    maxWidth: '70%',
                    animationDelay: `${i * 80}ms`,
                  }}
                />
              </div>
            )
          })}
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
          <p className="echo-chat-empty-text">{t('chat.noMessages')}</p>
          <p className="echo-chat-empty-hint">{t('chat.startHint')}</p>
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

      const nextMsg = messages[i + 1]
      const nextDateGroup = nextMsg ? formatDateGroup(nextMsg.created_at) : null
      const isGroupEnd = !nextMsg || nextMsg.sender_id !== msg.sender_id || nextDateGroup !== dateGroup

      elements.push(
        <MessageBubble
          key={String(msg.id)}
          msg={msg}
          isSelf={isSelf}
          isGroupStart={isGroupStart}
          isGroupEnd={isGroupEnd}
          peer={peer}
          currentUser={user}
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
        <button className="echo-chat-back-btn" onClick={onBack} aria-label={t('chat.goBack')}>
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
          <span className={`echo-presence-dot ${onlineUsers.has(peer.id) ? 'echo-presence-dot--online' : 'echo-presence-dot--offline'}`} />
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
              {loadingOlder ? t('chat.loadingOlder') : t('chat.loadOlder')}
            </button>
          </div>
        )}

        {renderMessages()}

        <div ref={messagesEndRef} />
      </div>

      {/* New message alert */}
      {newMessageAlert && (
        <button
          className="echo-new-message-alert"
          style={{ bottom: footerHeight + NEW_MESSAGE_ALERT_GAP_PX }}
          onClick={() => scrollToBottom()}
        >
          <ChevronDown size={14} />
          {t('chat.newMessages')}
        </button>
      )}

      <div ref={footerRef} className="echo-chat-footer">
        {/* Typing indicator */}
        {activeConversationId !== null && typingConversationIds.has(activeConversationId) && (
          <div className="echo-typing-indicator">
            <span className="echo-typing-dots">
              <span /><span /><span />
            </span>
            <span>{t('chat.typing', { name: peer.display_name || peer.username })}</span>
          </div>
        )}

        {/* Input */}
        <div className="echo-message-input-wrap">
          <div className="echo-message-textarea-wrap">
            <textarea
              ref={textareaRef}
              className="echo-message-textarea"
              placeholder={t('chat.placeholder')}
              rows={1}
              value={body}
              onChange={(e) => {
                setBody(e.target.value)
                handleTypingInput()
              }}
              onInput={handleInput}
              onKeyDown={handleKeyDown}
              onBlur={stopTyping}
            />
          </div>
          <button
            className="echo-message-send-btn"
            onClick={handleSend}
            disabled={!body.trim()}
            aria-label={t('chat.send')}
          >
            <Send size={18} />
          </button>
        </div>
      </div>
    </div>
  )
}

/* ── MessageBubble sub-component ── */

interface BubbleProps {
  msg: Message
  isSelf: boolean
  isGroupStart: boolean
  isGroupEnd: boolean
  peer: { id: number; username: string; display_name: string | null; avatar_url: string | null } | null | undefined
  currentUser: { username: string; display_name: string | null; avatar_url: string | null } | null
  recipientId: number
  retryMessage: (tempId: string, recipientId: number, body: string) => void
}

function MessageBubble({ msg, isSelf, isGroupStart, isGroupEnd, peer, currentUser, recipientId, retryMessage }: BubbleProps) {
  const { t, i18n } = useTranslation()
  const formatTime = (dateStr: string) =>
    new Date(dateStr).toLocaleTimeString(i18n.resolvedLanguage, { hour: '2-digit', minute: '2-digit', hour12: false })
  const isPending = msg._status === 'pending'
  const isFailed = msg._status === 'failed'

  const groupPos =
    isGroupStart && isGroupEnd ? 'solo'
    : isGroupStart ? 'first'
    : isGroupEnd ? 'last'
    : 'middle'

  const rowClass = [
    'echo-bubble-row',
    isSelf ? 'echo-bubble-row--self' : 'echo-bubble-row--other',
    isGroupEnd ? 'echo-bubble-row--group-end' : '',
  ]
    .filter(Boolean)
    .join(' ')

  const bubbleClass = [
    'echo-bubble',
    isSelf ? 'echo-bubble--self' : 'echo-bubble--other',
    `echo-bubble--${groupPos}`,
    isPending ? 'echo-bubble--pending' : '',
    isFailed ? 'echo-bubble--failed' : '',
  ]
    .filter(Boolean)
    .join(' ')

  const avatarInfo = isSelf ? currentUser : peer
  const avatarContent = avatarInfo ? (
    avatarInfo.avatar_url ? (
      <img src={avatarInfo.avatar_url} alt="" className="echo-avatar-img" />
    ) : (
      <span className="echo-avatar-initials">{initials(avatarInfo.display_name, avatarInfo.username)}</span>
    )
  ) : null

  return (
    <div className={rowClass}>
      {/* Left avatar (other's messages) */}
      {!isSelf && (
        <div className="echo-bubble-avatar-col echo-bubble-avatar-col--left">
          {isGroupEnd ? (
            <div className="echo-bubble-avatar">{avatarContent}</div>
          ) : (
            <div className="echo-bubble-avatar-spacer" />
          )}
        </div>
      )}

      <div style={{ display: 'flex', flexDirection: 'column', alignItems: isSelf ? 'flex-end' : 'flex-start', maxWidth: '65%', minWidth: 0 }}>
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
                <AlertCircle size={12} style={{ color: 'rgba(var(--echo-error-rgb), 0.7)' }} />
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
            {t('chat.retry')}
          </button>
        )}
      </div>

      {/* Right avatar (self messages) */}
      {isSelf && (
        <div className="echo-bubble-avatar-col echo-bubble-avatar-col--right">
          {isGroupEnd ? (
            <div className="echo-bubble-avatar">{avatarContent}</div>
          ) : (
            <div className="echo-bubble-avatar-spacer" />
          )}
        </div>
      )}
    </div>
  )
}
