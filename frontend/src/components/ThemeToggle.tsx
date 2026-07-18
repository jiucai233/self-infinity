import { useState } from 'react'
import { resolveInitialTheme, setTheme, type Theme } from '../theme'

export default function ThemeToggle() {
  const [theme, setThemeState] = useState<Theme>(() => resolveInitialTheme())

  function toggle() {
    const next: Theme = theme === 'light' ? 'dark' : 'light'
    setTheme(next)
    setThemeState(next)
  }

  return (
    <button
      onClick={toggle}
      aria-label={theme === 'light' ? '切换为深色主题' : '切换为浅色主题'}
      style={{
        position: 'fixed',
        bottom: 16,
        right: 16,
        zIndex: 100,
      }}
    >
      {theme === 'light' ? '☀' : '☾'}
    </button>
  )
}
