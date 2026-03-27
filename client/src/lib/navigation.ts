const HOME_TAB_QUERY_KEY = 'tab'
const AUTH_REDIRECT_QUERY_KEY = 'redirect'
const DEFAULT_HOME_TAB = 'chats'
const HOME_TABS = ['chats', 'friends', 'requests', 'search'] as const
const AUTH_ROUTE_PREFIXES = ['/login', '/register'] as const

export type HomeTab = (typeof HOME_TABS)[number]

export function parseHomeTab(value: string | null): HomeTab {
  if (value && HOME_TABS.includes(value as HomeTab)) {
    return value as HomeTab
  }

  return DEFAULT_HOME_TAB
}

export function buildHomeTabSearch(searchParams: URLSearchParams, tab: HomeTab) {
  // tab 是主页的 URL 状态源，默认 chats 不写进 query，避免首页链接变脏。
  const next = new URLSearchParams(searchParams)

  if (tab === DEFAULT_HOME_TAB) {
    next.delete(HOME_TAB_QUERY_KEY)
  } else {
    next.set(HOME_TAB_QUERY_KEY, tab)
  }

  const search = next.toString()
  return search ? `?${search}` : ''
}

export function buildAuthRedirectSearch(pathname: string, search: string) {
  const params = new URLSearchParams()
  params.set(AUTH_REDIRECT_QUERY_KEY, `${pathname}${search}`)
  return `?${params.toString()}`
}

export function getSafeRedirectTarget(value: string | null, fallback = '/') {
  // 只允许站内相对路径，顺手拦掉 auth 页，避免登录后跳回自己造成循环。
  if (!value || !value.startsWith('/') || value.startsWith('//')) {
    return fallback
  }

  if (AUTH_ROUTE_PREFIXES.some((route) => value === route || value.startsWith(`${route}?`))) {
    return fallback
  }

  return value
}

export function buildAuthPagePath(pathname: '/login' | '/register', redirectTarget: string) {
  if (redirectTarget === '/') {
    return pathname
  }

  const params = new URLSearchParams()
  params.set(AUTH_REDIRECT_QUERY_KEY, redirectTarget)
  return `${pathname}?${params.toString()}`
}
