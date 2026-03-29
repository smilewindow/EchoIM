import { useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import { MessageSquare } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { useAuthStore } from '@/stores/auth'
import { useChatStore } from '@/stores/chat'
import { useFriendRequestStore } from '@/stores/friendRequests'
import { apiFetch } from '@/lib/api'
import { buildHomeTabSearch, buildChatSearch, parseChatParam, parseHomeTab, type HomeTab } from '@/lib/navigation'
import { FriendsList } from '@/components/FriendsList'
import { FriendRequestsPanel } from '@/components/FriendRequestsPanel'
import { UserSearchPanel } from '@/components/UserSearchPanel'
import { ConversationList } from '@/components/ConversationList'
import { ChatView } from '@/components/ChatView'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import { LanguageSwitcher } from '@/components/LanguageSwitcher'

export function HomePage() {
  const { user, logout } = useAuthStore()
  const { t } = useTranslation()
  const [showLogoutConfirm, setShowLogoutConfirm] = useState(false)
  const navigate = useNavigate()
  const location = useLocation()
  const [searchParams] = useSearchParams()
  const displayName = user?.display_name || user?.username || ''
  const avatarUrl = user?.avatar_url

  const { activeConversationId, activePeer, conversations, conversationsLoading, fetchConversations, selectConversation, selectPeer, clearChat } =
    useChatStore()

  const activeTab = parseHomeTab(searchParams.get('tab'))
  const [friendCount, setFriendCount] = useState(0)
  const requestCount = useFriendRequestStore((s) => s.incoming.length)
  const friendsVersion = useFriendRequestStore((s) => s.friendsVersion)

  const chatActive = activeConversationId !== null || activePeer !== null

  // Fetch conversations and friend requests on mount
  useEffect(() => {
    fetchConversations()
    useFriendRequestStore.getState().fetchAll()
  }, [fetchConversations])

  // Re-fetch friend count whenever a friend request is accepted (from any tab)
  useEffect(() => {
    if (friendsVersion === 0) return
    let cancelled = false
    apiFetch<{ id: number }[]>('/friends')
      .then((data) => { if (!cancelled) setFriendCount(data.length) })
      .catch(() => {})
    return () => { cancelled = true }
  }, [friendsVersion])

  const handleBack = () => {
    clearChat()
  }

  useEffect(() => {
    const normalizedSearch = buildHomeTabSearch(new URLSearchParams(location.search), activeTab)

    if (location.search === normalizedSearch) {
      return
    }

    navigate(
      {
        pathname: location.pathname,
        search: normalizedSearch,
      },
      { replace: true },
    )
  }, [activeTab, location.pathname, location.search, navigate])

  // URL → Store: restore active chat after conversations are loaded
  const chatRestored = useRef(false)

  useEffect(() => {
    if (conversationsLoading) return

    const chatId = parseChatParam(searchParams.get('chat'))

    if (chatId === null || chatId === activeConversationId) {
      chatRestored.current = true
      return
    }

    const exists = conversations.some((c) => c.id === chatId)
    if (exists) {
      selectConversation(chatId)
    } else {
      // Invalid/stale chatId — clean up the URL
      navigate(
        { pathname: location.pathname, search: buildChatSearch(searchParams, null) },
        { replace: true },
      )
    }
    chatRestored.current = true
    // Only run when conversations finish loading, not on every activeConversationId change.
    // Once selectConversation fires, the Store → URL effect takes over.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [conversationsLoading])

  // Store → URL: keep ?chat= in sync with activeConversationId
  useEffect(() => {
    if (!chatRestored.current) return

    const params = new URLSearchParams(window.location.search)
    if (parseChatParam(params.get('chat')) === activeConversationId) return

    navigate(
      { pathname: location.pathname, search: buildChatSearch(params, activeConversationId) },
      { replace: true },
    )
  }, [activeConversationId, location.pathname, navigate])

  const updateActiveTab = (tab: HomeTab) => {
    navigate({
      pathname: location.pathname,
      search: buildHomeTabSearch(searchParams, tab),
    })
  }

  const tabs: { key: HomeTab; label: string; icon: React.ReactNode }[] = [
    {
      key: 'chats',
      label: t('home.tabs.chats'),
      icon: <MessageSquare size={16} />,
    },
    {
      key: 'friends',
      label: t('home.tabs.friends'),
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
      label: t('home.tabs.requests'),
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
      label: t('home.tabs.search'),
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
            <button
              onClick={() =>
                navigate({
                  pathname: '/profile',
                  search: location.search,
                })
              }
              className="echo-sidebar-profile-link"
              title={t('home.editProfile')}
            >
              <div className="echo-sidebar-avatar">
                {avatarUrl ? (
                  <img src={avatarUrl} alt="" className="echo-avatar-img" />
                ) : (
                  displayName.slice(0, 2).toUpperCase()
                )}
              </div>
              <div className="flex-1 min-w-0" style={{ textAlign: 'left' }}>
                <p className="echo-sidebar-name">{displayName}</p>
                <p className="echo-sidebar-status">{t('home.online')}</p>
              </div>
            </button>
            <LanguageSwitcher />
            <button onClick={() => setShowLogoutConfirm(true)} className="echo-logout-btn" title={t('home.signOut')}>
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
              onClick={() => updateActiveTab(tab.key)}
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
                updateActiveTab('chats')
              }}
            />
          )}
          {activeTab === 'requests' && (
            <FriendRequestsPanel />
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
            <p className="echo-main-sub">{t('home.placeholder')}</p>
          </div>
        )}
      </main>

      <ConfirmDialog
        open={showLogoutConfirm}
        title={t('home.signOut')}
        message={t('home.signOutConfirm')}
        confirmText={t('home.signOut')}
        cancelText={t('home.cancel')}
        onConfirm={logout}
        onCancel={() => setShowLogoutConfirm(false)}
      />
    </div>
  )
}
