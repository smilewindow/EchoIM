import { useEffect, useState } from 'react'
import { Navigate, Outlet } from 'react-router-dom'
import { ApiError } from '@/lib/api'
import { useAuthStore } from '@/stores/auth'

function getRestoreSessionError(err: unknown) {
  if (err instanceof ApiError) {
    if (err.status >= 500) return 'Server error while restoring your session.'
    return err.message
  }

  if (err instanceof Error) return err.message
  return 'Failed to restore your session.'
}

export function ProtectedRoute() {
  const { token, user, fetchMe, logout } = useAuthStore()
  const [loadError, setLoadError] = useState<string | null>(null)
  const [retryKey, setRetryKey] = useState(0)

  useEffect(() => {
    if (!token || user) return

    let cancelled = false

    fetchMe().catch((err) => {
      if (cancelled) return

      if (err instanceof ApiError && (err.status === 401 || err.status === 404)) {
        logout()
        return
      }

      setLoadError(getRestoreSessionError(err))
    })

    return () => {
      cancelled = true
    }
  }, [token, user, fetchMe, logout, retryKey])

  if (!token) return <Navigate to="/login" replace />
  if (user) return <Outlet />

  if (loadError) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-6">
        <div className="w-full max-w-md rounded-3xl border border-border/70 bg-card/95 p-6 shadow-xl backdrop-blur">
          <div className="space-y-2">
            <h1 className="text-xl font-semibold text-foreground">Unable to open EchoIM</h1>
            <p className="text-sm leading-6 text-muted-foreground">
              {loadError}
            </p>
          </div>

          <div className="mt-6 flex flex-col gap-3 sm:flex-row">
            <button
              type="button"
              onClick={() => {
                setLoadError(null)
                setRetryKey((key) => key + 1)
              }}
              className="inline-flex flex-1 items-center justify-center rounded-xl bg-foreground px-4 py-2.5 text-sm font-medium text-background transition hover:opacity-90"
            >
              Retry
            </button>
            <button
              type="button"
              onClick={logout}
              className="inline-flex flex-1 items-center justify-center rounded-xl border border-border px-4 py-2.5 text-sm font-medium text-foreground transition hover:bg-muted"
            >
              Back to login
            </button>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen items-center justify-center text-muted-foreground">
      Loading…
    </div>
  )
}
