import { useState, useEffect } from 'react'
import { Toaster } from '@/components/ui/sonner'

function isDark() {
  return document.documentElement.classList.contains('dark')
}

function isMobileViewport() {
  return window.matchMedia('(max-width: 640px)').matches
}

export function ThemedToaster() {
  const [theme, setTheme] = useState<'dark' | 'light'>(() => (isDark() ? 'dark' : 'light'))
  const [mobile, setMobile] = useState<boolean>(() => isMobileViewport())

  useEffect(() => {
    const observer = new MutationObserver(() => {
      const next = isDark() ? 'dark' : 'light'
      setTheme((prev) => (prev === next ? prev : next))
    })
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] })
    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    const mediaQuery = window.matchMedia('(max-width: 640px)')
    const syncViewport = () => setMobile(mediaQuery.matches)

    syncViewport()
    mediaQuery.addEventListener('change', syncViewport)
    return () => mediaQuery.removeEventListener('change', syncViewport)
  }, [])

  return (
    <Toaster
      position={mobile ? 'top-center' : 'top-right'}
      theme={theme}
      richColors
      offset={16}
      mobileOffset={{
        top: 'max(16px, env(safe-area-inset-top))',
        left: 16,
        right: 16,
      }}
    />
  )
}
