import { useCallback, useEffect, useState } from 'react'
import { apiFetch } from '@/lib/api'
import { usePresenceStore } from '@/stores/presence'
import { useFriendRequestStore } from '@/stores/friendRequests'

interface Friend {
  id: number
  username: string
  display_name: string
  avatar_url: string
}

interface Props {
  onCountChange?: (count: number) => void
  onSelectFriend?: (friend: Friend) => void
}

export function FriendsList({ onCountChange, onSelectFriend }: Props) {
  const [friends, setFriends] = useState<Friend[]>([])
  const [loading, setLoading] = useState(true)
  const onlineUsers = usePresenceStore((s) => s.onlineUsers)
  const friendsVersion = useFriendRequestStore((s) => s.friendsVersion)

  const fetchFriends = useCallback(async () => {
    try {
      const data = await apiFetch<Friend[]>('/friends')
      setFriends(data)
      onCountChange?.(data.length)
    } catch {
      // ignore
    } finally {
      setLoading(false)
    }
  }, [onCountChange])

  useEffect(() => {
    fetchFriends()
  }, [fetchFriends, friendsVersion])

  const initials = (friend: Friend) => {
    const name = friend.display_name || friend.username
    return name.slice(0, 2).toUpperCase()
  }

  if (loading) {
    return (
      <div className="echo-empty-state">
        <div className="echo-spinner" />
      </div>
    )
  }

  if (friends.length === 0) {
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
          <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
          <path d="M16 3.13a4 4 0 0 1 0 7.75" />
        </svg>
        <p className="echo-empty-text">No friends yet</p>
        <p className="echo-empty-hint">Search for users to add friends</p>
      </div>
    )
  }

  return (
    <div className="flex-1 overflow-y-auto echo-scroll px-2 py-2">
      {friends.map((friend, i) => (
        <div
          key={friend.id}
          className="echo-friend-row"
          style={{ animationDelay: `${i * 30}ms` }}
          onClick={() => onSelectFriend?.(friend)}
        >
          <div className="echo-avatar-wrap">
            <div
              className="echo-avatar"
              title={friend.display_name || friend.username}
            >
              {friend.avatar_url ? (
                <img
                  src={friend.avatar_url}
                  alt=""
                  className="echo-avatar-img"
                />
              ) : (
                <span className="echo-avatar-initials">
                  {initials(friend)}
                </span>
              )}
            </div>
            <span className={`echo-presence-dot ${onlineUsers.has(friend.id) ? 'echo-presence-dot--online' : 'echo-presence-dot--offline'}`} />
          </div>
          <div className="flex-1 min-w-0">
            <p className="echo-user-name">
              {friend.display_name || friend.username}
            </p>
            {friend.display_name && (
              <p className="echo-user-handle">@{friend.username}</p>
            )}
          </div>
        </div>
      ))}
    </div>
  )
}
