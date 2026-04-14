import { useEffect, useRef } from 'react'
import { createPortal } from 'react-dom'
import { useTranslation } from 'react-i18next'

interface LightboxProps {
  src: string
  onClose: () => void
}

export function Lightbox({ src, onClose }: LightboxProps) {
  const { t } = useTranslation()
  const closeBtnRef = useRef<HTMLButtonElement>(null)
  const triggerRef = useRef<HTMLElement | null>(null)
  const prevOverflowRef = useRef<string>('')

  useEffect(() => {
    // Save trigger element for focus restoration
    triggerRef.current = document.activeElement as HTMLElement

    // Body scroll lock
    prevOverflowRef.current = document.body.style.overflow
    document.body.style.overflow = 'hidden'

    // Move focus to close button
    closeBtnRef.current?.focus()

    // Esc key handler
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose()
    }
    document.addEventListener('keydown', handleKeyDown)

    return () => {
      document.removeEventListener('keydown', handleKeyDown)
      document.body.style.overflow = prevOverflowRef.current
      triggerRef.current?.focus()
    }
  }, [onClose])

  return createPortal(
    <div
      className="echo-lightbox-overlay"
      role="dialog"
      aria-modal="true"
      aria-label={t('chat.imagePreview')}
      onClick={onClose}
    >
      <button
        ref={closeBtnRef}
        className="echo-lightbox-close"
        aria-label={t('common.close')}
        onClick={onClose}
      >
        ✕
      </button>
      {/* Stop click from bubbling to overlay so clicking the image doesn't close */}
      <img
        className="echo-lightbox-img"
        src={src}
        alt={t('chat.imagePreview')}
        onClick={e => e.stopPropagation()}
        draggable={false}
      />
    </div>,
    document.body,
  )
}
