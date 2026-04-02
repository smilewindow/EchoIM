import { useTranslation } from 'react-i18next'
import { Languages } from 'lucide-react'

export function LanguageSwitcher() {
  const { t, i18n } = useTranslation()
  const next = i18n.resolvedLanguage?.startsWith('zh') ? 'en' : 'zh'

  return (
    <button
      onClick={() => i18n.changeLanguage(next)}
      className="echo-lang-btn"
      title={t(`language.${next}`)}
    >
      <Languages size={16} />
    </button>
  )
}
