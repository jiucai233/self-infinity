import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  applyTheme,
  getStoredTheme,
  getSystemDefaultTheme,
  resolveInitialTheme,
  setTheme,
} from './theme'

describe('theme', () => {
  beforeEach(() => {
    window.localStorage.clear()
    delete document.documentElement.dataset.theme
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  describe('getSystemDefaultTheme', () => {
    it('returns light for a daytime hour', () => {
      vi.setSystemTime(new Date(2026, 6, 19, 12, 0, 0))
      expect(getSystemDefaultTheme()).toBe('light')
    })

    it('returns dark for a nighttime hour', () => {
      vi.setSystemTime(new Date(2026, 6, 19, 22, 0, 0))
      expect(getSystemDefaultTheme()).toBe('dark')
    })

    it('treats the 6:00 boundary as light and 18:00 boundary as dark', () => {
      vi.setSystemTime(new Date(2026, 6, 19, 6, 0, 0))
      expect(getSystemDefaultTheme()).toBe('light')

      vi.setSystemTime(new Date(2026, 6, 19, 18, 0, 0))
      expect(getSystemDefaultTheme()).toBe('dark')
    })
  })

  describe('getStoredTheme', () => {
    it('returns null when nothing is stored', () => {
      expect(getStoredTheme()).toBeNull()
    })

    it('returns the stored theme when present', () => {
      window.localStorage.setItem('self-infinity-theme', 'light')
      expect(getStoredTheme()).toBe('light')
    })
  })

  describe('resolveInitialTheme', () => {
    it('prefers a stored override over the system-time default', () => {
      vi.setSystemTime(new Date(2026, 6, 19, 12, 0, 0)) // daytime -> would default to light
      window.localStorage.setItem('self-infinity-theme', 'dark')
      expect(resolveInitialTheme()).toBe('dark')
    })

    it('falls back to the system-time default when nothing is stored', () => {
      vi.setSystemTime(new Date(2026, 6, 19, 22, 0, 0))
      expect(resolveInitialTheme()).toBe('dark')
    })
  })

  describe('applyTheme / setTheme', () => {
    it('applyTheme sets the data-theme attribute without persisting', () => {
      applyTheme('light')
      expect(document.documentElement.dataset.theme).toBe('light')
      expect(getStoredTheme()).toBeNull()
    })

    it('setTheme applies and persists the theme', () => {
      setTheme('dark')
      expect(document.documentElement.dataset.theme).toBe('dark')
      expect(getStoredTheme()).toBe('dark')
    })
  })
})
