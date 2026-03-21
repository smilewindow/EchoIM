import { type ChangeEvent, type ReactNode } from 'react'

const ACCENT = '#E8943A'
const BG_DARK = '#08090F'
const BG_FORM = '#0D0E17'
const TEXT = '#F0EDE6'
const TEXT_DIM = 'rgba(240,237,230,0.42)'

function Wordmark() {
  return (
    <span
      style={{
        fontFamily: "'Syne', sans-serif",
        fontWeight: 800,
        fontSize: '22px',
        letterSpacing: '-0.01em',
        color: TEXT,
      }}
    >
      Echo<span style={{ color: ACCENT }}>IM</span>
    </span>
  )
}

export function AuthLayout({
  children,
  heading,
  subheading,
}: {
  children: ReactNode
  heading: string
  subheading: string
}) {
  return (
    <div style={{ display: 'flex', minHeight: '100vh', background: BG_DARK, color: TEXT }}>
      {/* ── Brand panel (desktop only) ── */}
      <div
        style={{
          display: 'none',
          width: '54%',
          flexDirection: 'column',
          justifyContent: 'space-between',
          position: 'relative',
          overflow: 'hidden',
          padding: '56px',
          borderRight: '1px solid rgba(255,255,255,0.05)',
        }}
        className="lg:flex!"
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
          {/* Beacon */}
          <div
            style={{
              position: 'absolute',
              width: '12px',
              height: '12px',
              borderRadius: '50%',
              background: ACCENT,
              zIndex: 1,
              animation: 'home-beacon-pulse 2.8s ease-in-out infinite',
            }}
          />
          {/* Expanding rings */}
          {[0, 1, 2, 3, 4].map(i => (
            <div
              key={i}
              style={{
                position: 'absolute',
                width: '12px',
                height: '12px',
                borderRadius: '50%',
                border: `1px solid ${ACCENT}28`,
                animation: 'echo-ring-large 4.8s cubic-bezier(0.2, 0.5, 0.4, 0.9) infinite',
                animationDelay: `${i * 0.96}s`,
              }}
            />
          ))}
        </div>

        {/* Logo */}
        <div style={{ position: 'relative', zIndex: 2 }}>
          <Wordmark />
        </div>

        {/* Tagline */}
        <div style={{ position: 'relative', zIndex: 2 }}>
          <p
            style={{
              fontFamily: "'Syne', sans-serif",
              fontWeight: 800,
              fontSize: 'clamp(30px, 3.2vw, 46px)',
              lineHeight: 1.15,
              letterSpacing: '-0.02em',
              color: TEXT,
              marginBottom: '16px',
            }}
          >
            Every message
            <br />
            <span style={{ color: ACCENT }}>finds its echo.</span>
          </p>
          <p
            style={{
              fontSize: '12px',
              letterSpacing: '0.08em',
              textTransform: 'uppercase',
              color: 'rgba(240,237,230,0.28)',
            }}
          >
            Real-time 1-on-1 messaging
          </p>
        </div>
      </div>

      {/* ── Form panel ── */}
      <div
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'center',
          padding: '48px 32px',
          background: BG_FORM,
          animation: 'auth-fade-up 0.55s cubic-bezier(0.16, 1, 0.3, 1) both',
        }}
        className="lg:px-16!"
      >
        {/* Mobile-only logo */}
        <div className="lg:hidden" style={{ marginBottom: '48px' }}>
          <Wordmark />
        </div>

        <div style={{ width: '100%', maxWidth: '340px', margin: '0 auto' }} className="lg:mx-0!">
          <h1
            style={{
              fontFamily: "'Syne', sans-serif",
              fontWeight: 700,
              fontSize: '26px',
              letterSpacing: '-0.01em',
              marginBottom: '8px',
              color: TEXT,
            }}
          >
            {heading}
          </h1>
          <p style={{ fontSize: '14px', color: TEXT_DIM, marginBottom: '40px' }}>{subheading}</p>
          {children}
        </div>
      </div>
    </div>
  )
}

export function AuthField({
  id,
  label,
  type = 'text',
  autoComplete,
  required,
  minLength,
  value,
  onChange,
}: {
  id: string
  label: string
  type?: string
  autoComplete?: string
  required?: boolean
  minLength?: number
  value: string
  onChange: (e: ChangeEvent<HTMLInputElement>) => void
}) {
  return (
    <div className="auth-field">
      <label
        htmlFor={id}
        style={{
          display: 'block',
          fontSize: '10px',
          letterSpacing: '0.1em',
          textTransform: 'uppercase',
          color: 'rgba(240,237,230,0.36)',
          marginBottom: '8px',
          fontWeight: 500,
        }}
      >
        {label}
      </label>
      <input
        id={id}
        type={type}
        autoComplete={autoComplete}
        required={required}
        minLength={minLength}
        value={value}
        onChange={onChange}
        style={{
          width: '100%',
          background: 'transparent',
          border: 'none',
          outline: 'none',
          color: TEXT,
          fontSize: '15px',
          lineHeight: 1.5,
          padding: '2px 0',
          caretColor: ACCENT,
        }}
      />
    </div>
  )
}

export function AuthSubmitButton({
  loading,
  label,
  loadingLabel,
}: {
  loading: boolean
  label: string
  loadingLabel: string
}) {
  return (
    <button
      type="submit"
      disabled={loading}
      style={{
        width: '100%',
        padding: '13px 24px',
        background: loading ? `${ACCENT}55` : ACCENT,
        color: '#08090F',
        border: 'none',
        borderRadius: '4px',
        fontSize: '14px',
        fontWeight: 700,
        letterSpacing: '0.02em',
        cursor: loading ? 'not-allowed' : 'pointer',
        transition: 'background 0.15s ease, transform 0.1s ease',
        fontFamily: 'inherit',
      }}
      onMouseEnter={e => {
        if (!loading) (e.currentTarget as HTMLButtonElement).style.background = '#F0A050'
      }}
      onMouseLeave={e => {
        if (!loading) (e.currentTarget as HTMLButtonElement).style.background = ACCENT
      }}
      onMouseDown={e => {
        if (!loading) (e.currentTarget as HTMLButtonElement).style.transform = 'scale(0.98)'
      }}
      onMouseUp={e => {
        if (!loading) (e.currentTarget as HTMLButtonElement).style.transform = 'scale(1)'
      }}
    >
      {loading ? loadingLabel : label}
    </button>
  )
}
