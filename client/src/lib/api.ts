const API_BASE = '/api'

export class ApiError extends Error {
  constructor(message: string, public status: number) {
    super(message)
  }
}

export async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = localStorage.getItem('token')
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string>),
  }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch(`${API_BASE}${path}`, { ...options, headers })
  const data = await res.json()
  if (!res.ok) throw new ApiError((data as { error?: string }).error ?? 'Request failed', res.status)
  return data as T
}
