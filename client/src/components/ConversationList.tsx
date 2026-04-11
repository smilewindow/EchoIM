import { useCallback } from 'react'
import { MessageSquare } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { useChatStore } from '@/stores/chat'
import { usePresenceStore } from '@/stores/presence'

const SKELETON_NAME_WIDTHS = [75, 60, 90, 55, 80, 65]
const SKELETON_PREVIEW_WIDTHS = [50, 40, 65, 35, 55, 45]

function useFormatRelativeTime() {
  const { t, i18n } = useTranslation()

  return (dateStr: string | null): string => {
    if (!dateStr) return ''
    const date = new Date(dateStr)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffSec = Math.floor(diffMs / 1000)
    const diffMin = Math.floor(diffSec / 60)
    const diffHr = Math.floor(diffMin / 60)

    if (diffSec < 60) return t('conversations.justNow')
    if (diffMin < 60) return `${diffMin}m`
    if (diffHr < 24) return `${diffHr}h`

    const yesterday = new Date(now)
    yesterday.setDate(yesterday.getDate() - 1)
    if (
      date.getDate() === yesterday.getDate() &&
      date.getMonth() === yesterday.getMonth() &&
      date.getFullYear() === yesterday.getFullYear()
    ) {
      return t('common.yesterday')
    }

    return date.toLocaleDateString(i18n.resolvedLanguage, { month: 'short', day: 'numeric' })
  }
}

export function ConversationList() {
  const { conversations, conversationsLoading, activeConversationId, selectConversation } =
    useChatStore()
  const { t } = useTranslation()
  const onlineUsers = usePresenceStore((s) => s.onlineUsers)
  const formatRelativeTime = useFormatRelativeTime()

  const handleSelect = useCallback(
    (id: number) => {
      selectConversation(id)
    },
    [selectConversation],
  )

  const initials = (displayName: string | null, username: string) => {
    const name = displayName || username
    return name.slice(0, 2).toUpperCase()
  }

  if (conversationsLoading) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', flex: 1, overflow: 'hidden' }}>
        <div className="echo-section-label">{t('conversations.label')}</div>
        <div className="px-2 py-1">
          {SKELETON_NAME_WIDTHS.map((w, i) => (
            <div key={i} className="echo-skeleton-row" style={{ animationDelay: `${i * 100}ms` }}>
              <div className="echo-skeleton echo-skeleton-circle" style={{ width: 36, height: 36, flexShrink: 0 }} />
              <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 6 }}>
                <div className="echo-skeleton" style={{ width: `${w}%`, height: 12 }} />
                <div className="echo-skeleton" style={{ width: `${SKELETON_PREVIEW_WIDTHS[i]}%`, height: 10 }} />
              </div>
            </div>
          ))}
        </div>
      </div>
    )
  }

  if (conversations.length === 0) {
    return (
      <div className="echo-empty-state">
        <MessageSquare
          size={32}
          className="echo-empty-icon"
          strokeWidth={1.5}
        />
        <p className="echo-empty-text">{t('conversations.empty')}</p>
        <p className="echo-empty-hint">{t('conversations.emptyHint')}</p>
      </div>
    )
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, overflow: 'hidden' }}>
      <div className="echo-section-label">{t('conversations.label')}</div>
      <div className="flex-1 overflow-y-auto echo-scroll px-2 py-1">
        {conversations.map((conv, i) => (
          <div
            key={conv.id}
            className={`echo-conversation-row${activeConversationId === conv.id ? ' echo-conversation-row--active' : ''}`}
            style={{ animationDelay: `${i * 25}ms` }}
            onClick={() => handleSelect(conv.id)}
          >
            <div className="echo-avatar-wrap">
              <div className="echo-avatar" title={conv.peer_display_name || conv.peer_username}>
                {conv.peer_avatar_url ? (
                  <img src={conv.peer_avatar_url} alt="" className="echo-avatar-img" />
                ) : (
                  <span className="echo-avatar-initials">
                    {initials(conv.peer_display_name, conv.peer_username)}
                  </span>
                )}
              </div>
              <span className={`echo-presence-dot ${onlineUsers.has(conv.peer_id) ? 'echo-presence-dot--online' : 'echo-presence-dot--offline'}`} />
            </div>

            <div className="echo-conversation-info">
              <p className="echo-conversation-name">
                {conv.peer_display_name || conv.peer_username}
              </p>
              <p className="echo-conversation-preview">
                {conv.last_message_body ?? t('conversations.noMessages')}
              </p>
            </div>

            <div className="echo-conversation-meta">
              <span className="echo-conversation-time">
                {formatRelativeTime(conv.last_message_at)}
              </span>
              {conv.unread_count > 0 && (
                <span className="echo-badge">{conv.unread_count}</span>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
