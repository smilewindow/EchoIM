import { useState } from 'react'
import { toast } from 'sonner'
import { apiFetch } from '@/lib/api'
import { useFriendRequestStore } from '@/stores/friendRequests'

export function FriendRequestsPanel() {
  const incoming = useFriendRequestStore((s) => s.incoming)
  const sent = useFriendRequestStore((s) => s.sent)
  const history = useFriendRequestStore((s) => s.history)
  const initialized = useFriendRequestStore((s) => s.initialized)

  const [respondingId, setRespondingId] = useState<number | null>(null)
  const [showHistory, setShowHistory] = useState(false)

  const respond = async (id: number, status: 'accepted' | 'declined') => {
    setRespondingId(id)
    try {
      await apiFetch(`/friend-requests/${id}`, {
        method: 'PUT',
        body: JSON.stringify({ status }),
      })
      // 不做乐观更新——服务端会广播 WS 事件给操作方，由 store 统一处理
    } catch {
      toast.error('Failed to respond to request')
    } finally {
      setRespondingId(null)
    }
  }

  const initials = (name: string) => name.slice(0, 2).toUpperCase()

  const timeAgo = (dateStr: string) => {
    const diff = Date.now() - new Date(dateStr).getTime()
    const mins = Math.floor(diff / 60000)
    if (mins < 1) return 'just now'
    if (mins < 60) return `${mins}m ago`
    const hrs = Math.floor(mins / 60)
    if (hrs < 24) return `${hrs}h ago`
    const days = Math.floor(hrs / 24)
    return `${days}d ago`
  }

  if (!initialized) {
    return (
      <div className="echo-empty-state">
        <div className="echo-spinner" />
      </div>
    )
  }

  const hasContent = incoming.length > 0 || sent.length > 0 || history.length > 0

  if (!hasContent) {
    return (
      <div className="echo-empty-state">
        <svg
          width="32"
          height="32"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          className="echo-empty-icon"
        >
          <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
          <circle cx="9" cy="7" r="4" />
          <line x1="19" x2="19" y1="8" y2="14" />
          <line x1="22" x2="16" y1="11" y2="11" />
        </svg>
        <p className="echo-empty-text">No requests yet</p>
      </div>
    )
  }

  return (
    <div className="flex-1 overflow-y-auto echo-scroll px-2 py-2">
      {/* Pending requests */}
      {incoming.length > 0 && (
        <>
          <p className="echo-section-label">
            Pending
            <span className="echo-section-count">{incoming.length}</span>
          </p>
          {incoming.map((req, i) => (
            <div
              key={req.id}
              className="echo-request-row"
              style={{ animationDelay: `${i * 50}ms` }}
            >
              <div
                className="echo-avatar"
                title={req.display_name || req.username}
              >
                {req.avatar_url ? (
                  <img
                    src={req.avatar_url}
                    alt=""
                    className="echo-avatar-img"
                  />
                ) : (
                  <span className="echo-avatar-initials">
                    {initials(req.display_name || req.username)}
                  </span>
                )}
              </div>
              <div className="flex-1 min-w-0">
                <p className="echo-user-name">
                  {req.display_name || req.username}
                </p>
                <p className="echo-user-handle">
                  @{req.username} · {timeAgo(req.created_at)}
                </p>
              </div>
              <div className="flex gap-1.5">
                <button
                  onClick={() => respond(req.id, 'accepted')}
                  disabled={respondingId === req.id}
                  className="echo-action-btn echo-action-btn--accept"
                >
                  Accept
                </button>
                <button
                  onClick={() => respond(req.id, 'declined')}
                  disabled={respondingId === req.id}
                  className="echo-action-btn echo-action-btn--decline"
                >
                  Decline
                </button>
              </div>
            </div>
          ))}
        </>
      )}

      {/* Sent (outgoing pending) */}
      {sent.length > 0 && (
        <>
          <p className="echo-section-label">
            Sent
            <span className="echo-section-count">{sent.length}</span>
          </p>
          {sent.map((req, i) => (
            <div
              key={req.id}
              className="echo-request-row"
              style={{ animationDelay: `${i * 50}ms` }}
            >
              <div
                className="echo-avatar"
                title={req.display_name || req.username}
              >
                {req.avatar_url ? (
                  <img
                    src={req.avatar_url}
                    alt=""
                    className="echo-avatar-img"
                  />
                ) : (
                  <span className="echo-avatar-initials">
                    {initials(req.display_name || req.username)}
                  </span>
                )}
              </div>
              <div className="flex-1 min-w-0">
                <p className="echo-user-name">
                  {req.display_name || req.username}
                </p>
                <p className="echo-user-handle">
                  @{req.username} · {timeAgo(req.created_at)}
                </p>
              </div>
              <span className="echo-status-pill echo-status-pill--pending">
                Pending
              </span>
            </div>
          ))}
        </>
      )}

      {/* History toggle */}
      {history.length > 0 && (
        <>
          <button
            onClick={() => setShowHistory((v) => !v)}
            className="echo-history-toggle"
          >
            <span>History</span>
            <span className="echo-section-count">{history.length}</span>
            <svg
              width="12"
              height="12"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2.5"
              className={`echo-chevron ${showHistory ? 'echo-chevron--open' : ''}`}
            >
              <polyline points="6 9 12 15 18 9" />
            </svg>
          </button>

          {showHistory &&
            history.map((req, i) => (
              <div
                key={req.id}
                className="echo-request-row echo-request-row--history"
                style={{ animationDelay: `${i * 30}ms` }}
              >
                <div
                  className="echo-avatar echo-avatar--muted"
                  title={req.display_name || req.username}
                >
                  {req.avatar_url ? (
                    <img
                      src={req.avatar_url}
                      alt=""
                      className="echo-avatar-img"
                    />
                  ) : (
                    <span className="echo-avatar-initials">
                      {initials(req.display_name || req.username)}
                    </span>
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="echo-user-name echo-user-name--muted">
                    {req.display_name || req.username}
                  </p>
                  <p className="echo-user-handle">
                    {req.direction === 'sent' ? 'Sent' : 'Received'} ·{' '}
                    {timeAgo(req.updated_at)}
                  </p>
                </div>
                <span
                  className={`echo-status-pill ${req.status === 'accepted' ? 'echo-status-pill--accepted' : 'echo-status-pill--declined'}`}
                >
                  {req.status === 'accepted' ? 'Accepted' : 'Declined'}
                </span>
              </div>
            ))}
        </>
      )}
    </div>
  )
}
