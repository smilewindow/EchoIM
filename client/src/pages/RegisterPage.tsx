import { useState, type FormEvent } from 'react'
import { Link, Navigate, useNavigate, useSearchParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { useAuthStore } from '@/stores/auth'
import { buildAuthPagePath, getSafeRedirectTarget } from '@/lib/navigation'
import { AuthLayout, AuthField, AuthSubmitButton } from '@/components/AuthLayout'

export function RegisterPage() {
  const { token, register } = useAuthStore()
  const { t } = useTranslation()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const [inviteCode, setInviteCode] = useState('')
  const [username, setUsername] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const redirectTarget = getSafeRedirectTarget(searchParams.get('redirect'))

  if (token) return <Navigate to={redirectTarget} replace />

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      await register(username, email, password, inviteCode)
      navigate(redirectTarget, { replace: true })
    } catch (err) {
      setError(err instanceof Error ? err.message : t('auth.register.failed'))
    } finally {
      setLoading(false)
    }
  }

  return (
    <AuthLayout heading={t('auth.register.heading')} subheading={t('auth.register.subheading')}>
      <form onSubmit={handleSubmit}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '28px', marginBottom: '36px' }}>
          {error && (
            <p
              style={{
                fontSize: '13px',
                color: 'rgba(var(--echo-error-rgb), 0.85)',
                padding: '10px 14px',
                background: 'rgba(var(--echo-error-rgb), 0.08)',
                borderRadius: '4px',
                margin: 0,
              }}
            >
              {error}
            </p>
          )}
          <AuthField
            id="inviteCode"
            label={t('auth.register.inviteCode')}
            type="text"
            autoComplete="off"
            required
            value={inviteCode}
            onChange={e => setInviteCode(e.target.value)}
          />
          <AuthField
            id="username"
            label={t('auth.register.username')}
            type="text"
            autoComplete="username"
            required
            minLength={3}
            value={username}
            onChange={e => setUsername(e.target.value)}
          />
          <AuthField
            id="email"
            label={t('auth.register.email')}
            type="email"
            autoComplete="email"
            required
            value={email}
            onChange={e => setEmail(e.target.value)}
          />
          <AuthField
            id="password"
            label={t('auth.register.password')}
            type="password"
            autoComplete="new-password"
            required
            minLength={8}
            value={password}
            onChange={e => setPassword(e.target.value)}
          />
        </div>

        <AuthSubmitButton loading={loading} label={t('auth.register.submit')} loadingLabel={t('auth.register.submitting')} />

        <p style={{ marginTop: '24px', fontSize: '13px', color: 'rgba(var(--echo-text-rgb), 0.38)', textAlign: 'center' }}>
          {t('auth.register.hasAccount')}{' '}
          <Link
            to={buildAuthPagePath('/login', redirectTarget)}
            style={{ color: 'var(--echo-accent)', textDecoration: 'none', fontWeight: 500 }}
            onMouseEnter={e => ((e.target as HTMLElement).style.textDecoration = 'underline')}
            onMouseLeave={e => ((e.target as HTMLElement).style.textDecoration = 'none')}
          >
            {t('auth.register.signIn')}
          </Link>
        </p>
      </form>
    </AuthLayout>
  )
}
