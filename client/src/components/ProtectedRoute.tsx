import { useEffect } from 'react'
import { Navigate, Outlet } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth'
import { ApiError } from '@/lib/api'

export function ProtectedRoute() {
  const { token, user, fetchMe, logout } = useAuthStore()

  useEffect(() => {
    if (token && !user) {
      fetchMe().catch((err) => {
        if (err instanceof ApiError && err.status === 401) logout()
      })
    }
  }, [token, user, fetchMe, logout])

  if (!token) return <Navigate to="/login" replace />
  if (!user) return <div className="flex h-screen items-center justify-center text-muted-foreground">Loading…</div>
  return <Outlet />
}
