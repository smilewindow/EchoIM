import { useEffect, useState } from 'react'
import { MessageSquare } from 'lucide-react'
import { useAuthStore } from '@/stores/auth'
import { useChatStore } from '@/stores/chat'
import { apiFetch } from '@/lib/api'
import { useWebSocket } from '@/hooks/useWebSocket'
import { FriendsList } from '@/components/FriendsList'
import { FriendRequestsPanel } from '@/components/FriendRequestsPanel'
import { UserSearchPanel } from '@/components/UserSearchPanel'
import { ConversationList } from '@/components/ConversationList'
import { ChatView } from '@/components/ChatView'

type Tab = 'chats' | 'friends' | 'requests' | 'search'

export function HomePage() {
  const { user, logout } = useAuthStore()
  const displayName = user?.display_name || user?.username || ''

  const { activeConversationId, activePeer, fetchConversations, selectPeer, clearChat } =
    useChatStore()

  useWebSocket()

  const [activeTab, setActiveTab] = useState<Tab>('chats')
  const [requestCount, setRequestCount] = useState(0)
  const [friendCount, setFriendCount] = useState(0)

  const chatActive = activeConversationId !== null || activePeer !== null

  // Fetch conversations on mount
  useEffect(() => {
    fetchConversations()
  }, [fetchConversations])

  // Poll for friend request count
  useEffect(() => {
    let cancelled = false
    const poll = async () => {
      try {
        const data = await apiFetch<{ id: number }[]>('/friend-requests')
        if (!cancelled) setRequestCount(data.length)
      } catch {
        // ignore
      }
    }
    poll()
    const interval = setInterval(poll, 30000)
    return () => {
      cancelled = true
      clearInterval(interval)
    }
  }, [])

  const handleRequestCountChange = (count: number) => {
    setRequestCount(count)
  }

  const handleBack = () => {
    clearChat()
  }

  const tabs: { key: Tab; label: string; icon: React.ReactNode }[] = [
    {
      key: 'chats',
      label: 'Chats',
      icon: <MessageSquare size={16} />,
    },
    {
      key: 'friends',
      label: 'Friends',
      icon: (
        <svg
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
          <circle cx="9" cy="7" r="4" />
          <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
          <path d="M16 3.13a4 4 0 0 1 0 7.75" />
        </svg>
      ),
    },
    {
      key: 'requests',
      label: 'Requests',
      icon: (
        <svg
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
          <circle cx="9" cy="7" r="4" />
          <line x1="19" x2="19" y1="8" y2="14" />
          <line x1="22" x2="16" y1="11" y2="11" />
        </svg>
      ),
    },
    {
      key: 'search',
      label: 'Search',
      icon: (
        <svg
          width="16"
          height="16"
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
      ),
    },
  ]

  return (
    <div className={`echo-shell${chatActive ? ' echo-shell--chat-active' : ''}`}>
      {/* ─── Sidebar ─── */}
      <aside className="echo-sidebar">
        {/* User header */}
        <div className="echo-sidebar-header">
          <div className="echo-sidebar-user">
            <div className="echo-sidebar-avatar">
              {displayName.slice(0, 2).toUpperCase()}
            </div>
            <div className="flex-1 min-w-0">
              <p className="echo-sidebar-name">{displayName}</p>
              <p className="echo-sidebar-status">Online</p>
            </div>
            <button onClick={logout} className="echo-logout-btn" title="Sign out">
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
                <polyline points="16 17 21 12 16 7" />
                <line x1="21" x2="9" y1="12" y2="12" />
              </svg>
            </button>
          </div>
        </div>

        {/* Tab bar */}
        <nav className="echo-tab-bar">
          {tabs.map((tab) => (
            <button
              key={tab.key}
              onClick={() => setActiveTab(tab.key)}
              className={`echo-tab ${activeTab === tab.key ? 'echo-tab--active' : ''}`}
            >
              {tab.icon}
              <span>{tab.label}</span>
              {tab.key === 'friends' && friendCount > 0 && (
                <span className="echo-count">{friendCount}</span>
              )}
              {tab.key === 'requests' && requestCount > 0 && (
                <span className="echo-badge">{requestCount}</span>
              )}
            </button>
          ))}
        </nav>

        {/* Tab content */}
        <div className="echo-sidebar-content">
          {activeTab === 'chats' && <ConversationList />}
          {activeTab === 'friends' && (
            <FriendsList
              onCountChange={setFriendCount}
              onSelectFriend={(friend) => {
                selectPeer({
                  id: friend.id,
                  username: friend.username,
                  display_name: friend.display_name,
                  avatar_url: friend.avatar_url,
                })
                setActiveTab('chats')
              }}
            />
          )}
          {activeTab === 'requests' && (
            <FriendRequestsPanel onCountChange={handleRequestCountChange} />
          )}
          {activeTab === 'search' && <UserSearchPanel />}
        </div>
      </aside>

      {/* ─── Main content area ─── */}
      <main className="echo-main">
        {chatActive ? (
          <ChatView onBack={handleBack} />
        ) : (
          <div className="echo-main-placeholder">
            <div className="echo-main-beacon-wrap">
              <div className="echo-main-beacon" />
              {[0, 1, 2].map((i) => (
                <div
                  key={i}
                  className="echo-main-ring"
                  style={{ animationDelay: `${i * 1.6}s` }}
                />
              ))}
            </div>
            <h2 className="echo-main-title">
              Echo<span className="echo-main-accent">IM</span>
            </h2>
            <p className="echo-main-sub">Select a friend to start a conversation</p>
          </div>
        )}
      </main>
    </div>
  )
}
