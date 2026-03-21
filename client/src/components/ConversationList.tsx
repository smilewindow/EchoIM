import { useCallback } from 'react'
import { MessageSquare } from 'lucide-react'
import { useChatStore } from '@/stores/chat'

function formatRelativeTime(dateStr: string | null): string {
  if (!dateStr) return ''
  const date = new Date(dateStr)
  const now = new Date()
  const diffMs = now.getTime() - date.getTime()
  const diffSec = Math.floor(diffMs / 1000)
  const diffMin = Math.floor(diffSec / 60)
  const diffHr = Math.floor(diffMin / 60)

  if (diffSec < 60) return 'Just now'
  if (diffMin < 60) return `${diffMin}m`
  if (diffHr < 24) return `${diffHr}h`

  const yesterday = new Date(now)
  yesterday.setDate(yesterday.getDate() - 1)
  if (
    date.getDate() === yesterday.getDate() &&
    date.getMonth() === yesterday.getMonth() &&
    date.getFullYear() === yesterday.getFullYear()
  ) {
    return 'Yesterday'
  }

  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' })
}

export function ConversationList() {
  const { conversations, conversationsLoading, activeConversationId, selectConversation } =
    useChatStore()

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
      <div className="echo-empty-state">
        <div className="echo-spinner" />
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
        <p className="echo-empty-text">No conversations yet</p>
        <p className="echo-empty-hint">Message a friend to start chatting</p>
      </div>
    )
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, overflow: 'hidden' }}>
      <div className="echo-section-label">Chats</div>
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
            </div>

            <div className="echo-conversation-info">
              <p className="echo-conversation-name">
                {conv.peer_display_name || conv.peer_username}
              </p>
              <p className="echo-conversation-preview">
                {conv.last_message_body ?? 'No messages yet'}
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
