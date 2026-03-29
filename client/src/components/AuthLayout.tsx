import { type ChangeEvent, type ReactNode } from 'react'
import { useTranslation } from 'react-i18next'
import { LanguageSwitcher } from '@/components/LanguageSwitcher'

function Wordmark() {
  return (
    <span
      style={{
        fontFamily: "'Syne', sans-serif",
        fontWeight: 800,
        fontSize: '22px',
        letterSpacing: '-0.01em',
        color: 'var(--echo-text)',
      }}
    >
      Echo<span style={{ color: 'var(--echo-accent)' }}>IM</span>
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
  const { t } = useTranslation()

  return (
    <div
      style={{
        display: 'flex',
        minHeight: '100vh',
        background: 'var(--echo-bg)',
        color: 'var(--echo-text)',
        position: 'relative',
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      {/* ── Brand panel (full-screen background) ── */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'space-between',
          overflow: 'hidden',
          padding: '56px',
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
          {/* Beacon */}
          <div
            style={{
              position: 'absolute',
              width: '12px',
              height: '12px',
              borderRadius: '50%',
              background: 'var(--echo-accent)',
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
                border: '1px solid rgba(var(--echo-accent-rgb), 0.16)',
                animation: 'echo-ring-large 4.8s cubic-bezier(0.2, 0.5, 0.4, 0.9) infinite',
                animationDelay: `${i * 0.96}s`,
              }}
            />
          ))}
        </div>

        <div style={{ position: 'relative', zIndex: 2, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Wordmark />
          <LanguageSwitcher />
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
              color: 'var(--echo-text)',
              marginBottom: '16px',
            }}
          >
            {t('auth.tagline1')}
            <br />
            <span style={{ color: 'var(--echo-accent)' }}>{t('auth.tagline2')}</span>
          </p>
          <p
            style={{
              fontSize: '12px',
              letterSpacing: '0.08em',
              textTransform: 'uppercase',
              color: 'rgba(var(--echo-text-rgb), 0.28)',
            }}
          >
            {t('auth.taglineSub')}
          </p>
        </div>
      </div>

      {/* ── Form panel (glass card) ── */}
      <div className="echo-auth-glass-card">
        <h1
          style={{
            fontFamily: "'Syne', sans-serif",
            fontWeight: 700,
            fontSize: '26px',
            letterSpacing: '-0.01em',
            marginBottom: '8px',
            color: 'var(--echo-text)',
          }}
        >
          {heading}
        </h1>
        <p style={{ fontSize: '14px', color: 'rgba(var(--echo-text-rgb), 0.42)', marginBottom: '40px' }}>{subheading}</p>
        {children}
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
          color: 'rgba(var(--echo-text-rgb), 0.36)',
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
          color: 'var(--echo-text)',
          fontSize: '15px',
          lineHeight: 1.5,
          padding: '2px 0',
          caretColor: 'var(--echo-accent)',
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
        background: loading ? 'rgba(var(--echo-accent-rgb), 0.33)' : 'var(--echo-accent)',
        color: 'var(--echo-accent-text)',
        border: 'none',
        borderRadius: '12px',
        fontSize: '14px',
        fontWeight: 700,
        letterSpacing: '0.02em',
        cursor: loading ? 'not-allowed' : 'pointer',
        transition: 'background 0.15s ease, transform 0.1s ease',
        fontFamily: 'inherit',
      }}
      onMouseEnter={e => {
        if (!loading) (e.currentTarget as HTMLButtonElement).style.background = 'var(--echo-accent-hover)'
      }}
      onMouseLeave={e => {
        if (!loading) (e.currentTarget as HTMLButtonElement).style.background = 'var(--echo-accent)'
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
