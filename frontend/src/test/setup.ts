import '@testing-library/jest-dom/vitest'
import { afterEach } from 'vitest'
import { cleanup } from '@testing-library/react'

afterEach(() => {
  cleanup()
})

// Newer Node versions ship an experimental global `localStorage` that can
// shadow jsdom's own Storage implementation and end up non-functional in
// the test environment (methods missing on the returned object). Detect
// that and fall back to a minimal in-memory Storage polyfill so tests that
// exercise localStorage-backed features work regardless of the Node version
// running them.
if (typeof window.localStorage?.setItem !== 'function') {
  const store = new Map<string, string>()
  const memoryStorage: Storage = {
    getItem: (key: string) => (store.has(key) ? store.get(key)! : null),
    setItem: (key: string, value: string) => {
      store.set(key, String(value))
    },
    removeItem: (key: string) => {
      store.delete(key)
    },
    clear: () => {
      store.clear()
    },
    key: (index: number) => Array.from(store.keys())[index] ?? null,
    get length() {
      return store.size
    },
  }
  Object.defineProperty(window, 'localStorage', {
    value: memoryStorage,
    configurable: true,
  })
}
