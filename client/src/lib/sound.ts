export type SoundType = 'slide' | 'double' | 'bubble' | 'crisp'

let audioCtx: AudioContext | null = null

function getAudioContext(): AudioContext | null {
  if (typeof window === 'undefined') return null
  if (!audioCtx) {
    try {
      audioCtx = new AudioContext()
    } catch {
      return null
    }
  }
  return audioCtx
}

function makeVoice(ctx: AudioContext, type: OscillatorType = 'sine') {
  const osc = ctx.createOscillator()
  const gain = ctx.createGain()
  osc.connect(gain)
  gain.connect(ctx.destination)
  osc.type = type
  return { osc, gain }
}

function playSlide(ctx: AudioContext) {
  const { osc, gain } = makeVoice(ctx)
  osc.frequency.setValueAtTime(880, ctx.currentTime)
  osc.frequency.exponentialRampToValueAtTime(660, ctx.currentTime + 0.3)
  gain.gain.setValueAtTime(0.6, ctx.currentTime)
  gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.5)
  osc.start(ctx.currentTime)
  osc.stop(ctx.currentTime + 0.5)
}

function playDouble(ctx: AudioContext) {
  const t = ctx.currentTime
  for (const [start, freq] of [[0, 660], [0.22, 880]] as [number, number][]) {
    const { osc, gain } = makeVoice(ctx)
    osc.frequency.setValueAtTime(freq, t + start)
    gain.gain.setValueAtTime(0.5, t + start)
    gain.gain.exponentialRampToValueAtTime(0.001, t + start + 0.18)
    osc.start(t + start)
    osc.stop(t + start + 0.18)
  }
}

function playBubble(ctx: AudioContext) {
  const { osc, gain } = makeVoice(ctx)
  osc.frequency.setValueAtTime(350, ctx.currentTime)
  osc.frequency.exponentialRampToValueAtTime(160, ctx.currentTime + 0.25)
  gain.gain.setValueAtTime(0.7, ctx.currentTime)
  gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.3)
  osc.start(ctx.currentTime)
  osc.stop(ctx.currentTime + 0.3)
}

function playCrisp(ctx: AudioContext) {
  const { osc, gain } = makeVoice(ctx, 'triangle')
  osc.frequency.setValueAtTime(1200, ctx.currentTime)
  gain.gain.setValueAtTime(0.5, ctx.currentTime)
  gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.18)
  osc.start(ctx.currentTime)
  osc.stop(ctx.currentTime + 0.18)
}

const PLAYERS: Record<SoundType, (ctx: AudioContext) => void> = {
  slide: playSlide,
  double: playDouble,
  bubble: playBubble,
  crisp: playCrisp,
}

function playWithContext(type: SoundType, ctx: AudioContext) {
  const play = () => PLAYERS[type](ctx)
  if (ctx.state === 'suspended') {
    ctx.resume().then(play).catch(() => {})
  } else {
    play()
  }
}

let lastPlayedAt = 0
const PLAY_MIN_INTERVAL_MS = 300

export function playNotification(type: SoundType) {
  const now = Date.now()
  if (now - lastPlayedAt < PLAY_MIN_INTERVAL_MS) return
  lastPlayedAt = now

  const ctx = getAudioContext()
  if (!ctx) return
  playWithContext(type, ctx)
}

export function previewSound(type: SoundType) {
  const ctx = getAudioContext()
  if (!ctx) return
  playWithContext(type, ctx)
}
