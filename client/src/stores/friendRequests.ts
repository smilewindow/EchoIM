import { create } from 'zustand'
import { apiFetch } from '@/lib/api'

export interface FriendRequest {
  id: number
  sender_id: number
  recipient_id: number
  status: 'pending' | 'accepted' | 'declined'
  created_at: string
  updated_at: string
  username: string
  display_name: string
  avatar_url: string
}

export interface HistoryRequest extends FriendRequest {
  direction: 'sent' | 'received'
}

interface FriendRequestState {
  incoming: FriendRequest[]
  sent: FriendRequest[]
  history: HistoryRequest[]
  friendsVersion: number
  initialized: boolean

  fetchAll: () => Promise<void>
  reset: () => void
  addIncoming: (req: FriendRequest) => void
  addSent: (req: FriendRequest) => void
  handleAccepted: (req: FriendRequest, direction: 'sent' | 'received') => void
  handleDeclined: (req: FriendRequest, direction: 'sent' | 'received') => void
}

// 竞态保护：每次 fetchAll 调用前递增，回写时检查是否过时
let _fetchId = 0

export const useFriendRequestStore = create<FriendRequestState>((set) => ({
  incoming: [],
  sent: [],
  history: [],
  friendsVersion: 0,
  initialized: false,

  fetchAll: async () => {
    const myId = ++_fetchId
    try {
      const [incomingData, sentData, historyData] = await Promise.all([
        apiFetch<FriendRequest[]>('/friend-requests'),
        apiFetch<FriendRequest[]>('/friend-requests/sent'),
        apiFetch<HistoryRequest[]>('/friend-requests/history'),
      ])
      // 过时响应丢弃
      if (myId !== _fetchId) return
      set({ incoming: incomingData, sent: sentData, history: historyData, initialized: true })
    } catch {
      // fetch 失败也要解除 loading 状态，避免 UI 永远卡在 spinner
      if (myId === _fetchId) set({ initialized: true })
    }
  },

  reset: () => {
    ++_fetchId // 使任何进行中的 fetchAll 响应作废
    set({ incoming: [], sent: [], history: [], friendsVersion: 0, initialized: false })
  },

  addIncoming: (req) => {
    set((state) => {
      if (state.incoming.some((r) => r.id === req.id)) return state
      return { incoming: [req, ...state.incoming] }
    })
  },

  addSent: (req) => {
    set((state) => {
      if (state.sent.some((r) => r.id === req.id)) return state
      return { sent: [req, ...state.sent] }
    })
  },

  handleAccepted: (req, direction) => {
    set((state) => ({
      incoming: state.incoming.filter((r) => r.id !== req.id),
      sent: state.sent.filter((r) => r.id !== req.id),
      history: [{ ...req, direction }, ...state.history.filter((r) => r.id !== req.id)],
      friendsVersion: state.friendsVersion + 1,
    }))
  },

  handleDeclined: (req, direction) => {
    set((state) => ({
      incoming: state.incoming.filter((r) => r.id !== req.id),
      sent: state.sent.filter((r) => r.id !== req.id),
      history: [{ ...req, direction }, ...state.history.filter((r) => r.id !== req.id)],
    }))
  },
}))
