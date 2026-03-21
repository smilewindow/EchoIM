import { useState, type FormEvent } from 'react'
import { Link, Navigate, useNavigate } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth'
import { AuthLayout, AuthField, AuthSubmitButton } from '@/components/AuthLayout'

export function RegisterPage() {
  const { token, register } = useAuthStore()
  const navigate = useNavigate()
  const [username, setUsername] = useState('')
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
      await register(username, email, password)
      navigate('/')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Registration failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <AuthLayout heading="Create account" subheading="Join EchoIM and start messaging in real time.">
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
            id="username"
            label="Username"
            type="text"
            autoComplete="username"
            required
            minLength={3}
            value={username}
            onChange={e => setUsername(e.target.value)}
          />
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
            autoComplete="new-password"
            required
            minLength={8}
            value={password}
            onChange={e => setPassword(e.target.value)}
          />
        </div>

        <AuthSubmitButton loading={loading} label="Create account" loadingLabel="Creating account…" />

        <p style={{ marginTop: '24px', fontSize: '13px', color: 'rgba(240,237,230,0.38)', textAlign: 'center' }}>
          Already have an account?{' '}
          <Link
            to="/login"
            style={{ color: '#E8943A', textDecoration: 'none', fontWeight: 500 }}
            onMouseEnter={e => ((e.target as HTMLElement).style.textDecoration = 'underline')}
            onMouseLeave={e => ((e.target as HTMLElement).style.textDecoration = 'none')}
          >
            Sign in
          </Link>
        </p>
      </form>
    </AuthLayout>
  )
}
