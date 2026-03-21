import { useCallback, useEffect, useRef, useState } from 'react'
import { apiFetch, ApiError } from '@/lib/api'

interface SearchUser {
  id: number
  username: string
  display_name: string
  avatar_url: string
}

export function UserSearchPanel() {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<SearchUser[]>([])
  const [loading, setLoading] = useState(false)
  const [sentIds, setSentIds] = useState<Set<number>>(new Set())
  const [sendingId, setSendingId] = useState<number | null>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const abortRef = useRef<AbortController | null>(null)
  const requestIdRef = useRef(0)

  const search = useCallback(async (q: string, requestId: number) => {
    if (q.trim().length < 2) {
      setResults([])
      return
    }

    const controller = new AbortController()
    abortRef.current = controller
    setLoading(true)
    try {
      const data = await apiFetch<SearchUser[]>(
        `/users/search?q=${encodeURIComponent(q.trim())}`,
        { signal: controller.signal },
      )
      if (requestId === requestIdRef.current) setResults(data)
    } catch (err) {
      if (err instanceof DOMException && err.name === 'AbortError') return
      if (requestId === requestIdRef.current) setResults([])
    } finally {
      if (requestId === requestIdRef.current) setLoading(false)
    }
  }, [])

  useEffect(() => {
    abortRef.current?.abort()
    const id = ++requestIdRef.current
    if (debounceRef.current) clearTimeout(debounceRef.current)
    if (query.trim().length < 2) {
      setResults([])
      setLoading(false)
      return
    }
    debounceRef.current = setTimeout(() => search(query, id), 300)
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current)
    }
  }, [query, search])

  const sendRequest = async (userId: number) => {
    setSendingId(userId)
    try {
      await apiFetch('/friend-requests', {
        method: 'POST',
        body: JSON.stringify({ recipient_id: userId }),
      })
      setSentIds((prev) => new Set(prev).add(userId))
    } catch (err) {
      // 409 means a request already exists — treat as sent
      if (err instanceof ApiError && err.status === 409) {
        setSentIds((prev) => new Set(prev).add(userId))
      }
      // other errors (500, network, etc.) leave the button enabled for retry
    } finally {
      setSendingId(null)
    }
  }

  const initials = (user: SearchUser) => {
    const name = user.display_name || user.username
    return name.slice(0, 2).toUpperCase()
  }

  return (
    <div className="flex flex-col h-full">
      {/* Search input */}
      <div className="p-4 pb-2">
        <div className="echo-search-wrap">
          <svg
            className="echo-search-icon"
            width="15"
            height="15"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <circle cx="11" cy="11" r="8" />
            <path d="m21 21-4.3-4.3" />
          </svg>
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search by username…"
            className="echo-search-input"
            autoFocus
          />
          {query && (
            <button
              onClick={() => setQuery('')}
              className="echo-search-clear"
              aria-label="Clear search"
            >
              ×
            </button>
          )}
        </div>
      </div>

      {/* Results */}
      <div className="flex-1 overflow-y-auto echo-scroll px-2 pb-2">
        {loading && query.trim().length >= 2 && (
          <div className="echo-empty-state">
            <div className="echo-spinner" />
          </div>
        )}

        {!loading && query.trim().length >= 2 && results.length === 0 && (
          <div className="echo-empty-state">
            <p className="echo-empty-text">No users found</p>
          </div>
        )}

        {!loading && query.trim().length < 2 && (
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
              <circle cx="11" cy="11" r="8" />
              <path d="m21 21-4.3-4.3" />
            </svg>
            <p className="echo-empty-text">
              Type at least 2 characters to search
            </p>
          </div>
        )}

        {results.map((user, i) => (
          <div
            key={user.id}
            className="echo-user-row"
            style={{ animationDelay: `${i * 40}ms` }}
          >
            <div className="echo-avatar" title={user.display_name || user.username}>
              {user.avatar_url ? (
                <img
                  src={user.avatar_url}
                  alt=""
                  className="echo-avatar-img"
                />
              ) : (
                <span className="echo-avatar-initials">{initials(user)}</span>
              )}
            </div>
            <div className="flex-1 min-w-0">
              <p className="echo-user-name">
                {user.display_name || user.username}
              </p>
              {user.display_name && (
                <p className="echo-user-handle">@{user.username}</p>
              )}
            </div>
            <button
              onClick={() => sendRequest(user.id)}
              disabled={sentIds.has(user.id) || sendingId === user.id}
              className={`echo-action-btn ${sentIds.has(user.id) ? 'echo-action-btn--sent' : ''}`}
            >
              {sentIds.has(user.id)
                ? 'Sent'
                : sendingId === user.id
                  ? '…'
                  : 'Add'}
            </button>
          </div>
        ))}
      </div>
    </div>
  )
}
