const API_BASE = '/api'

export class ApiError extends Error {
  constructor(message: string, public status: number) {
    super(message)
  }
}

export async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = localStorage.getItem('token')
  const headers: Record<string, string> = {
    ...(options.body !== undefined ? { 'Content-Type': 'application/json' } : {}),
    ...(options.headers as Record<string, string>),
  }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch(`${API_BASE}${path}`, { ...options, headers })

  if (!res.ok) {
    let message = 'Request failed'
    try {
      const data = await res.json() as { error?: string }
      if (data.error) message = data.error
    } catch {
      // non-JSON error body — use default message
    }
    throw new ApiError(message, res.status)
  }

  return await res.json() as T
}
