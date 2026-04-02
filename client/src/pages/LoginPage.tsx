import { useState, type FormEvent } from 'react'
import { Link, Navigate, useNavigate, useSearchParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { useAuthStore } from '@/stores/auth'
import { buildAuthPagePath, getSafeRedirectTarget } from '@/lib/navigation'
import { AuthLayout, AuthField, AuthSubmitButton } from '@/components/AuthLayout'

export function LoginPage() {
  const { token, login } = useAuthStore()
  const { t } = useTranslation()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
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
      await login(email, password)
      navigate(redirectTarget, { replace: true })
    } catch (err) {
      setError(err instanceof Error ? err.message : t('auth.login.failed'))
    } finally {
      setLoading(false)
    }
  }

  return (
    <AuthLayout heading={t('auth.login.heading')} subheading={t('auth.login.subheading')}>
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
            id="email"
            label={t('auth.login.email')}
            type="email"
            autoComplete="email"
            required
            value={email}
            onChange={e => setEmail(e.target.value)}
          />
          <AuthField
            id="password"
            label={t('auth.login.password')}
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={e => setPassword(e.target.value)}
          />
        </div>

        <AuthSubmitButton loading={loading} label={t('auth.login.submit')} loadingLabel={t('auth.login.submitting')} />

        <p style={{ marginTop: '24px', fontSize: '13px', color: 'rgba(var(--echo-text-rgb), 0.38)', textAlign: 'center' }}>
          {t('auth.login.noAccount')}{' '}
          <Link
            to={buildAuthPagePath('/register', redirectTarget)}
            style={{ color: 'var(--echo-accent)', textDecoration: 'none', fontWeight: 500 }}
            onMouseEnter={e => ((e.target as HTMLElement).style.textDecoration = 'underline')}
            onMouseLeave={e => ((e.target as HTMLElement).style.textDecoration = 'none')}
          >
            {t('auth.login.register')}
          </Link>
        </p>
      </form>
    </AuthLayout>
  )
}
