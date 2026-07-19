import { describe, expect, it } from 'vitest'
import { computeForceLayout } from './graphLayout'

describe('computeForceLayout', () => {
  it('returns a finite, in-bounds position for every node', () => {
    const ids = ['skill-1', 'skill-2', 'principle-1']
    const edges = [
      { source: 'skill-1', target: 'skill-2' },
      { source: 'principle-1', target: 'skill-1' },
    ]
    const positions = computeForceLayout(ids, edges, 800, 600, 50)

    expect(positions.size).toBe(3)
    for (const id of ids) {
      const pos = positions.get(id)!
      expect(pos).toBeDefined()
      expect(Number.isFinite(pos.x)).toBe(true)
      expect(Number.isFinite(pos.y)).toBe(true)
      expect(pos.x).toBeGreaterThanOrEqual(0)
      expect(pos.x).toBeLessThanOrEqual(800)
      expect(pos.y).toBeGreaterThanOrEqual(0)
      expect(pos.y).toBeLessThanOrEqual(600)
    }
  })

  it('is deterministic across repeated calls on the same input', () => {
    const ids = ['a', 'b', 'c', 'd']
    const edges = [{ source: 'a', target: 'b' }]
    const first = computeForceLayout(ids, edges, 400, 400, 100)
    const second = computeForceLayout(ids, edges, 400, 400, 100)
    for (const id of ids) {
      expect(first.get(id)).toEqual(second.get(id))
    }
  })

  it('handles an empty graph without throwing', () => {
    expect(computeForceLayout([], [], 400, 400).size).toBe(0)
  })
})
