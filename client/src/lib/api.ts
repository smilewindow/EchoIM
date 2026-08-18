const API_BASE = '/api'

export class ApiError extends Error {
  constructor(message: string, public status: number) {
    super(message)
  }
}

type ApiErrorResponse = {
  error: {
    code: string
    message: string
  }
}

async function readApiErrorMessage(res: Response, fallback: string): Promise<string> {
  try {
    const data = (await res.json()) as ApiErrorResponse
    return data.error.message
  } catch {
    // 非 JSON 响应没有服务端错误信息，只能保留调用方提供的通用提示。
    return fallback
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
    throw new ApiError(await readApiErrorMessage(res, 'Request failed'), res.status)
  }

  return await res.json() as T
}

export async function uploadAvatar(blob: Blob): Promise<{ avatar_url: string }> {
  const token = localStorage.getItem('token')
  const formData = new FormData()
  formData.append('avatar', blob, 'avatar.jpg')

  const res = await fetch(`${API_BASE}/upload/avatar`, {
    method: 'POST',
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: formData,
  })

  if (!res.ok) {
    throw new ApiError(await readApiErrorMessage(res, 'Upload failed'), res.status)
  }

  return (await res.json()) as { avatar_url: string }
}

export interface UploadedImage {
  mediaUrl: string
  mediaWidth: number
  mediaHeight: number
}

export async function uploadImageBlob(blob: Blob): Promise<UploadedImage | null> {
  const token = localStorage.getItem('token')
  const formData = new FormData()
  formData.append('file', blob, 'image.jpg')

  try {
    const res = await fetch(`${API_BASE}/upload/message-image`, {
      method: 'POST',
      headers: token ? { Authorization: `Bearer ${token}` } : {},
      body: formData,
    })

    if (!res.ok) return null

    const data = (await res.json()) as {
      media_url?: string
      media_width?: number
      media_height?: number
    }
    if (!data.media_url || !data.media_width || !data.media_height) return null
    return {
      mediaUrl: data.media_url,
      mediaWidth: data.media_width,
      mediaHeight: data.media_height,
    }
  } catch {
    return null
  }
}
