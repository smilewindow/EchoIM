import { useAuthStore } from '@/stores/auth'

const ACCENT = '#E8943A'
const BG = '#08090F'
const TEXT = '#F0EDE6'

export function HomePage() {
  const { user, logout } = useAuthStore()
  const displayName = user?.display_name || user?.username || ''

  return (
    <div
      style={{
        minHeight: '100vh',
        background: BG,
        color: TEXT,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      {/* Echo rings backdrop */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          pointerEvents: 'none',
        }}
      >
        <div
          style={{
            position: 'absolute',
            width: '12px',
            height: '12px',
            borderRadius: '50%',
            background: ACCENT,
            animation: 'home-beacon-pulse 2.8s ease-in-out infinite',
          }}
        />
        {[0, 1, 2, 3, 4].map(i => (
          <div
            key={i}
            style={{
              position: 'absolute',
              width: '12px',
              height: '12px',
              borderRadius: '50%',
              border: `1px solid ${ACCENT}20`,
              animation: 'echo-ring-large 5s cubic-bezier(0.2, 0.5, 0.4, 0.9) infinite',
              animationDelay: `${i * 1.0}s`,
            }}
          />
        ))}
      </div>

      {/* Content */}
      <div
        style={{
          position: 'relative',
          zIndex: 1,
          textAlign: 'center',
          animation: 'auth-fade-up 0.6s cubic-bezier(0.16, 1, 0.3, 1) both',
        }}
      >
        <p
          style={{
            fontSize: '12px',
            letterSpacing: '0.1em',
            textTransform: 'uppercase',
            color: 'rgba(240,237,230,0.3)',
            marginBottom: '20px',
          }}
        >
          Signed in as
        </p>
        <h1
          style={{
            fontFamily: "'Syne', sans-serif",
            fontWeight: 800,
            fontSize: 'clamp(36px, 6vw, 64px)',
            letterSpacing: '-0.02em',
            lineHeight: 1.1,
            marginBottom: '12px',
          }}
        >
          {displayName}
        </h1>
        <p
          style={{
            fontSize: '14px',
            color: 'rgba(240,237,230,0.35)',
            marginBottom: '48px',
            letterSpacing: '0.02em',
          }}
        >
          Chat UI arriving in Phase 9
        </p>

        <button
          onClick={logout}
          style={{
            padding: '10px 28px',
            background: 'transparent',
            border: '1px solid rgba(255,255,255,0.12)',
            borderRadius: '4px',
            color: 'rgba(240,237,230,0.55)',
            fontSize: '13px',
            letterSpacing: '0.04em',
            cursor: 'pointer',
            fontFamily: 'inherit',
            transition: 'border-color 0.15s ease, color 0.15s ease',
          }}
          onMouseEnter={e => {
            const btn = e.currentTarget as HTMLButtonElement
            btn.style.borderColor = `${ACCENT}60`
            btn.style.color = ACCENT
          }}
          onMouseLeave={e => {
            const btn = e.currentTarget as HTMLButtonElement
            btn.style.borderColor = 'rgba(255,255,255,0.12)'
            btn.style.color = 'rgba(240,237,230,0.55)'
          }}
        >
          Sign out
        </button>
      </div>

      {/* Wordmark bottom-right */}
      <div
        style={{
          position: 'absolute',
          bottom: '28px',
          right: '32px',
          fontFamily: "'Syne', sans-serif",
          fontWeight: 800,
          fontSize: '16px',
          color: 'rgba(240,237,230,0.15)',
          letterSpacing: '-0.01em',
        }}
      >
        Echo<span style={{ color: `${ACCENT}40` }}>IM</span>
      </div>
    </div>
  )
}
