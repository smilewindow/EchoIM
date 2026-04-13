import { create } from 'zustand'
import { previewSound, type SoundType } from '@/lib/sound'

export type SoundMode = 'off' | SoundType

const CYCLE: SoundMode[] = ['slide', 'double', 'bubble', 'crisp', 'off']
const STORAGE_KEY = 'echo_sound_mode'

function readMode(): SoundMode {
  const stored = localStorage.getItem(STORAGE_KEY)
  if (stored && CYCLE.includes(stored as SoundMode)) return stored as SoundMode
  // v1 stored a boolean muted flag; convert to the new multi-mode key on first load
  if (localStorage.getItem('echo_sound_muted') === 'true') {
    localStorage.setItem(STORAGE_KEY, 'off')
    localStorage.removeItem('echo_sound_muted')
    return 'off'
  }
  return 'slide'
}

interface SoundState {
  soundMode: SoundMode
  cycleSound: () => void
}

export const useSoundStore = create<SoundState>((set, get) => ({
  soundMode: readMode(),
  cycleSound: () => {
    const next = CYCLE[(CYCLE.indexOf(get().soundMode) + 1) % CYCLE.length]
    localStorage.setItem(STORAGE_KEY, next)
    set({ soundMode: next })
    if (next !== 'off') previewSound(next)
  },
}))

// Sync sound mode when another tab writes to localStorage
if (typeof window !== 'undefined') {
  window.addEventListener('storage', (e) => {
    if (e.key === STORAGE_KEY && e.newValue && CYCLE.includes(e.newValue as SoundMode)) {
      useSoundStore.setState({ soundMode: e.newValue as SoundMode })
    }
  })
}
