import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import ThemeToggle from './ThemeToggle'

describe('ThemeToggle', () => {
  beforeEach(() => {
    window.localStorage.clear()
    delete document.documentElement.dataset.theme
  })

  it('clicking flips the theme on <html> and persists it to localStorage', async () => {
    vi.setSystemTime(new Date(2026, 6, 19, 12, 0, 0)) // daytime -> initial theme is light
    const user = userEvent.setup()
    render(<ThemeToggle />)

    const button = screen.getByRole('button')
    await user.click(button)

    expect(document.documentElement.dataset.theme).toBe('dark')
    expect(window.localStorage.getItem('self-infinity-theme')).toBe('dark')

    await user.click(button)

    expect(document.documentElement.dataset.theme).toBe('light')
    expect(window.localStorage.getItem('self-infinity-theme')).toBe('light')
  })
})
