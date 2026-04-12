import { useState, useRef, type FormEvent, type ChangeEvent } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { ArrowLeft, Upload } from 'lucide-react'
import { toast } from 'sonner'
import { useTranslation } from 'react-i18next'
import { useAuthStore } from '@/stores/auth'
import { uploadAvatar, ApiError } from '@/lib/api'
import { compressImage, validateImageFile } from '@/lib/image'

function toAbsoluteUrl(url: string): string {
  if (url && url.startsWith('/')) return `${window.location.origin}${url}`
  return url
}

function toStoredAvatarUrl(url: string): string {
  if (!url || url.startsWith('/')) return url

  const parsedUrl = new URL(url)

  // 仅剥离真正同源的 origin，避免把文本前缀相同的外链误判成本地上传头像
  return parsedUrl.origin === window.location.origin
    ? `${parsedUrl.pathname}${parsedUrl.search}${parsedUrl.hash}`
    : url
}

export function ProfileEditPage() {
  const { user, updateProfile, fetchMe, logout } = useAuthStore()
  const { t } = useTranslation()
  const navigate = useNavigate()
  const location = useLocation()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [displayName, setDisplayName] = useState(user?.display_name ?? '')
  const [avatarUrl, setAvatarUrl] = useState(toAbsoluteUrl(user?.avatar_url ?? ''))
  const [loading, setLoading] = useState(false)
  const [uploadStatus, setUploadStatus] = useState<'idle' | 'compressing' | 'uploading'>('idle')

  const initials = (user?.display_name || user?.username || '').slice(0, 2).toUpperCase()

  const handleFileChange = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    // Validate file
    const validationError = validateImageFile(file)
    if (validationError) {
      const errorKey =
        validationError === 'INVALID_TYPE' ? 'profile.invalidFileType' : 'profile.fileTooLarge'
      toast.error(t(errorKey))
      if (fileInputRef.current) fileInputRef.current.value = ''
      return
    }

    try {
      // Compress (fallback to original file if Canvas APIs unavailable)
      setUploadStatus('compressing')
      let blob: Blob
      try {
        blob = await compressImage(file)
      } catch {
        blob = file
      }

      // Upload
      setUploadStatus('uploading')
      const result = await uploadAvatar(blob)

      // Update local state and refetch user
      setAvatarUrl(toAbsoluteUrl(result.avatar_url))
      await fetchMe()
      toast.success(t('profile.uploadSuccess'))
    } catch (err) {
      // Handle 401 - user no longer exists, logout
      if (err instanceof ApiError && err.status === 401) {
        logout()
      }
      toast.error(err instanceof Error ? err.message : t('profile.uploadFailed'))
    } finally {
      setUploadStatus('idle')
      if (fileInputRef.current) {
        fileInputRef.current.value = ''
      }
    }
  }

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      await updateProfile({
        display_name: displayName,
        avatar_url: toStoredAvatarUrl(avatarUrl),
      })
      toast.success(t('profile.updated'))
      navigate({
        pathname: '/',
        search: location.search,
      })
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t('profile.failed'))
    } finally {
      setLoading(false)
    }
  }

  const isUploading = uploadStatus !== 'idle'
  const uploadButtonText =
    uploadStatus === 'compressing'
      ? t('profile.compressing')
      : uploadStatus === 'uploading'
        ? t('profile.uploading')
        : t('profile.selectFile')

  return (
    <div className="echo-profile-page">
      <div className="echo-profile-card">
        <button
          onClick={() =>
            navigate({
              pathname: '/',
              search: location.search,
            })
          }
          className="echo-profile-back"
        >
          <ArrowLeft size={18} />
          <span>{t('profile.back')}</span>
        </button>

        <h1 className="echo-profile-heading">{t('profile.heading')}</h1>

        {/* Avatar upload section */}
        <div className="echo-profile-avatar-section">
          <div className="echo-profile-avatar-preview">
            {avatarUrl ? <img src={avatarUrl} alt="" /> : initials}
          </div>

          <input
            ref={fileInputRef}
            type="file"
            accept="image/jpeg,image/png,image/gif,image/webp"
            onChange={handleFileChange}
            className="echo-profile-file-input"
            disabled={isUploading}
          />

          <button
            type="button"
            onClick={() => fileInputRef.current?.click()}
            disabled={isUploading}
            className="echo-profile-upload-btn"
          >
            <Upload size={16} />
            <span>{uploadButtonText}</span>
          </button>

          <p className="echo-profile-upload-hint">{t('profile.uploadHint')}</p>
        </div>

        <form onSubmit={handleSubmit} className="echo-profile-form">
          <div className="auth-field">
            <label htmlFor="displayName" className="echo-profile-label">
              {t('profile.displayName')}
            </label>
            <input
              id="displayName"
              type="text"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              className="echo-profile-input"
              placeholder={user?.username}
            />
          </div>

          <div className="auth-field">
            <label htmlFor="avatarUrl" className="echo-profile-label">
              {t('profile.avatarUrl')}
            </label>
            <input
              id="avatarUrl"
              type="url"
              value={avatarUrl}
              onChange={(e) => setAvatarUrl(e.target.value)}
              className="echo-profile-input"
              placeholder="https://example.com/avatar.jpg"
            />
          </div>

          <button
            type="submit"
            disabled={loading || isUploading}
            className="echo-profile-submit"
          >
            {loading ? t('profile.saving') : t('profile.save')}
          </button>
        </form>
      </div>
    </div>
  )
}
