import { create } from 'zustand'
import { apiFetch } from '@/lib/api'

export interface User {
  id: number
  username: string
  email: string
  display_name: string | null
  avatar_url: string | null
}

interface AuthState {
  token: string | null
  user: User | null
  login: (email: string, password: string) => Promise<void>
  register: (username: string, email: string, password: string) => Promise<void>
  logout: () => void
  fetchMe: () => Promise<void>
}

export const useAuthStore = create<AuthState>((set) => ({
  token: localStorage.getItem('token'),
  user: null,

  login: async (email, password) => {
    const data = await apiFetch<{ token: string; user: User }>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    })
    localStorage.setItem('token', data.token)
    set({ token: data.token, user: data.user })
  },

  register: async (username, email, password) => {
    const data = await apiFetch<{ token: string; user: User }>('/auth/register', {
      method: 'POST',
      body: JSON.stringify({ username, email, password }),
    })
    localStorage.setItem('token', data.token)
    set({ token: data.token, user: data.user })
  },

  logout: () => {
    localStorage.removeItem('token')
    set({ token: null, user: null })
  },

  fetchMe: async () => {
    const user = await apiFetch<User>('/users/me')
    set({ user })
  },
}))
