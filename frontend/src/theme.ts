export type Theme = 'light' | 'dark'

const STORAGE_KEY = 'self-infinity-theme'

// Daytime window is 6:00 (inclusive) – 18:00 (exclusive) local wall-clock hour → light, else dark.
export function getSystemDefaultTheme(): Theme {
  const hour = new Date().getHours()
  return hour >= 6 && hour < 18 ? 'light' : 'dark'
}

export function getStoredTheme(): Theme | null {
  const stored = window.localStorage.getItem(STORAGE_KEY)
  return stored === 'light' || stored === 'dark' ? stored : null
}

export function resolveInitialTheme(): Theme {
  return getStoredTheme() ?? getSystemDefaultTheme()
}

export function applyTheme(theme: Theme): void {
  document.documentElement.dataset.theme = theme
}

export function setTheme(theme: Theme): void {
  applyTheme(theme)
  window.localStorage.setItem(STORAGE_KEY, theme)
}
