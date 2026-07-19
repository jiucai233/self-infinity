// Force-directed layout for the Knowledge Graph (Fruchterman-Reingold
// style: repulsion between every pair of nodes, attraction along edges,
// linear cooling). No charting library — the graph is small (skills +
// principles for a single user), so a synchronous in-browser simulation
// converges in a handful of milliseconds and needs no new dependency.

export interface GraphLayoutPosition {
  x: number
  y: number
}

interface LayoutNode extends GraphLayoutPosition {
  id: string
  vx: number
  vy: number
}

// Deterministic pseudo-random initial angle per node id (not Math.random)
// so the starting layout — and therefore the converged layout — is stable
// across re-renders of the same graph instead of jittering every reload.
function hashToUnit(id: string): number {
  let h = 0
  for (let i = 0; i < id.length; i++) {
    h = (h * 31 + id.charCodeAt(i)) | 0
  }
  return ((h >>> 0) % 10000) / 10000
}

export function computeForceLayout(
  nodeIds: string[],
  edges: { source: string; target: string }[],
  width: number,
  height: number,
  iterations = 300,
): Map<string, GraphLayoutPosition> {
  if (nodeIds.length === 0) return new Map()

  const cx = width / 2
  const cy = height / 2
  const radius = Math.min(width, height) / 2.5

  const nodes = new Map<string, LayoutNode>(
    nodeIds.map((id, i) => {
      const angle = hashToUnit(id) * Math.PI * 2 + i * 0.0001
      return [id, { id, x: cx + Math.cos(angle) * radius, y: cy + Math.sin(angle) * radius, vx: 0, vy: 0 }]
    }),
  )

  const validEdges = edges.filter((e) => nodes.has(e.source) && nodes.has(e.target))
  const area = width * height
  const k = Math.sqrt(area / Math.max(1, nodeIds.length)) * 0.6

  for (let iter = 0; iter < iterations; iter++) {
    const temperature = Math.max(0, 1 - iter / iterations) * (k / 2)

    // Repulsion between every pair — O(n^2), fine at this app's scale
    // (dozens of skills/principles, not thousands).
    const all = Array.from(nodes.values())
    for (let i = 0; i < all.length; i++) {
      for (let j = i + 1; j < all.length; j++) {
        const a = all[i]
        const b = all[j]
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dist = Math.sqrt(dx * dx + dy * dy) || 0.01
        const force = (k * k) / dist
        dx = (dx / dist) * force
        dy = (dy / dist) * force
        a.vx += dx
        a.vy += dy
        b.vx -= dx
        b.vy -= dy
      }
    }

    // Attraction along real edges only.
    for (const e of validEdges) {
      const a = nodes.get(e.source)!
      const b = nodes.get(e.target)!
      const dx = a.x - b.x
      const dy = a.y - b.y
      const dist = Math.sqrt(dx * dx + dy * dy) || 0.01
      const force = (dist * dist) / k
      const ux = dx / dist
      const uy = dy / dist
      a.vx -= ux * force * 0.5
      a.vy -= uy * force * 0.5
      b.vx += ux * force * 0.5
      b.vy += uy * force * 0.5
    }

    // Mild centering force so disconnected nodes don't drift off-canvas.
    for (const n of all) {
      n.vx += (cx - n.x) * 0.002
      n.vy += (cy - n.y) * 0.002
    }

    for (const n of all) {
      const speed = Math.sqrt(n.vx * n.vx + n.vy * n.vy) || 0.01
      const capped = Math.min(speed, temperature || 0.5)
      n.x += (n.vx / speed) * capped
      n.y += (n.vy / speed) * capped
      n.vx = 0
      n.vy = 0
      n.x = Math.max(24, Math.min(width - 24, n.x))
      n.y = Math.max(24, Math.min(height - 24, n.y))
    }
  }

  const result = new Map<string, GraphLayoutPosition>()
  for (const [id, n] of nodes) result.set(id, { x: n.x, y: n.y })
  return result
}
