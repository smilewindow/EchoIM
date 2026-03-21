import { useState, type FormEvent } from 'react'
import { Link, Navigate, useNavigate } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth'
import { AuthLayout, AuthField, AuthSubmitButton } from '@/components/AuthLayout'

export function LoginPage() {
  const { token, login } = useAuthStore()
  const navigate = useNavigate()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  if (token) return <Navigate to="/" replace />

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      await login(email, password)
      navigate('/')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <AuthLayout heading="Welcome back" subheading="Sign in to continue your conversations.">
      <form onSubmit={handleSubmit}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '28px', marginBottom: '36px' }}>
          {error && (
            <p
              style={{
                fontSize: '13px',
                color: '#F08070',
                padding: '10px 14px',
                background: 'rgba(240,128,112,0.08)',
                borderRadius: '4px',
                margin: 0,
              }}
            >
              {error}
            </p>
          )}
          <AuthField
            id="email"
            label="Email"
            type="email"
            autoComplete="email"
            required
            value={email}
            onChange={e => setEmail(e.target.value)}
          />
          <AuthField
            id="password"
            label="Password"
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={e => setPassword(e.target.value)}
          />
        </div>

        <AuthSubmitButton loading={loading} label="Sign in" loadingLabel="Signing in…" />

        <p style={{ marginTop: '24px', fontSize: '13px', color: 'rgba(240,237,230,0.38)', textAlign: 'center' }}>
          No account?{' '}
          <Link
            to="/register"
            style={{ color: '#E8943A', textDecoration: 'none', fontWeight: 500 }}
            onMouseEnter={e => ((e.target as HTMLElement).style.textDecoration = 'underline')}
            onMouseLeave={e => ((e.target as HTMLElement).style.textDecoration = 'none')}
          >
            Register
          </Link>
        </p>
      </form>
    </AuthLayout>
  )
}
