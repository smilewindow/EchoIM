import { Outlet } from 'react-router-dom'
import { useWebSocket } from '@/hooks/useWebSocket'

export function ProtectedLayout() {
  useWebSocket()
  return <Outlet />
}
