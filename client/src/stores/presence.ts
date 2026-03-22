import { create } from 'zustand'

interface PresenceState {
  onlineUsers: Set<number>
  setOnline: (userId: number) => void
  setOffline: (userId: number) => void
  isOnline: (userId: number) => boolean
  clearAll: () => void
}

export const usePresenceStore = create<PresenceState>((set, get) => ({
  onlineUsers: new Set(),

  setOnline: (userId) =>
    set((s) => {
      if (s.onlineUsers.has(userId)) return s
      return { onlineUsers: new Set([...s.onlineUsers, userId]) }
    }),

  setOffline: (userId) =>
    set((s) => {
      if (!s.onlineUsers.has(userId)) return s
      const next = new Set(s.onlineUsers)
      next.delete(userId)
      return { onlineUsers: next }
    }),

  isOnline: (userId) => get().onlineUsers.has(userId),

  clearAll: () => set({ onlineUsers: new Set() }),
}))
