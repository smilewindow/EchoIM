interface ConfirmDialogProps {
  open: boolean
  title: string
  message: string
  confirmText?: string
  cancelText?: string
  onConfirm: () => void
  onCancel: () => void
}

export function ConfirmDialog({
  open,
  title,
  message,
  confirmText = 'Confirm',
  cancelText = 'Cancel',
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  if (!open) return null

  return (
    <div className="echo-confirm-overlay" onClick={onCancel}>
      <div className="echo-confirm-card" onClick={e => e.stopPropagation()}>
        <p className="echo-confirm-title">{title}</p>
        <p className="echo-confirm-message">{message}</p>
        <div className="echo-confirm-actions">
          <button className="echo-confirm-btn-cancel" onClick={onCancel}>
            {cancelText}
          </button>
          <button className="echo-confirm-btn-confirm" onClick={onConfirm}>
            {confirmText}
          </button>
        </div>
      </div>
    </div>
  )
}
