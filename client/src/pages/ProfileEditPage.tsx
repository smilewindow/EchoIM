import { useState, type FormEvent } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { ArrowLeft } from 'lucide-react'
import { toast } from 'sonner'
import { useTranslation } from 'react-i18next'
import { useAuthStore } from '@/stores/auth'

export function ProfileEditPage() {
  const { user, updateProfile } = useAuthStore()
  const { t } = useTranslation()
  const navigate = useNavigate()
  const location = useLocation()
  const [displayName, setDisplayName] = useState(user?.display_name ?? '')
  const [avatarUrl, setAvatarUrl] = useState(user?.avatar_url ?? '')
  const [loading, setLoading] = useState(false)

  const initials = (user?.display_name || user?.username || '').slice(0, 2).toUpperCase()

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      await updateProfile({
        // 资料字段允许清空，空字符串必须原样提交给后端。
        display_name: displayName,
        avatar_url: avatarUrl,
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

  return (
    <div className="echo-profile-page">
      <div className="echo-profile-card">
        {/* Back button */}
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

        {/* Avatar preview */}
        <div className="echo-profile-avatar-preview">
          {avatarUrl ? (
            <img src={avatarUrl} alt="" />
          ) : (
            initials
          )}
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
              onChange={e => setDisplayName(e.target.value)}
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
              onChange={e => setAvatarUrl(e.target.value)}
              className="echo-profile-input"
              placeholder="https://example.com/avatar.jpg"
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="echo-profile-submit"
          >
            {loading ? t('profile.saving') : t('profile.save')}
          </button>
        </form>
      </div>
    </div>
  )
}
