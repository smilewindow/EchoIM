import { useState, useEffect } from 'react'
import { Toaster } from '@/components/ui/sonner'

function isDark() {
  return document.documentElement.classList.contains('dark')
}

export function ThemedToaster() {
  const [theme, setTheme] = useState<'dark' | 'light'>(() => (isDark() ? 'dark' : 'light'))

  useEffect(() => {
    const observer = new MutationObserver(() => {
      const next = isDark() ? 'dark' : 'light'
      setTheme((prev) => (prev === next ? prev : next))
    })
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] })
    return () => observer.disconnect()
  }, [])

  return <Toaster position="top-right" theme={theme} richColors />
}
