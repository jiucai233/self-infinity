import { useEffect, useMemo, useState } from 'react'
import { api } from '../api'
import { computeForceLayout } from '../graphLayout'
import type { GraphEdge, GraphNode, GraphResponse } from '../types'

// Repurposes the template's "Map" nav slot — a knowledge graph is, in a
// real sense, a map of everything you've learned. Renders the real skill
// tree (parent edges) plus the Archive's principles wired to the real node
// each one came from ("origin" edges, via Principle.source_session_id ->
// AuditSession.skill_id on the backend) and to any other node the same
// keyword-overlap heuristic app/agents/retrieval.py already uses for
// in-audit retrieval finds related ("related" edges) — no fabricated
// connections.
const WIDTH = 900
const HEIGHT = 620

const EDGE_STYLE: Record<GraphEdge['kind'], { stroke: string; dash?: string; width: number }> = {
  parent: { stroke: 'var(--text)', width: 2 },
  origin: { stroke: '#facc15', dash: '2 4', width: 1.5 },
  related: { stroke: 'var(--border-strong)', dash: '1 3', width: 1 },
}

function nodeRadius(node: GraphNode): number {
  return node.kind === 'principle' ? 7 : 10
}

export default function KnowledgeGraph({
  onOpenSkill,
}: {
  onOpenSkill: (skillId: number) => void
}) {
  const [data, setData] = useState<GraphResponse | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<GraphNode | null>(null)

  useEffect(() => {
    api
      .getGraph()
      .then(setData)
      .catch((e) => setError(String(e)))
  }, [])

  const positions = useMemo(() => {
    if (!data) return new Map()
    return computeForceLayout(
      data.nodes.map((n) => n.id),
      data.edges,
      WIDTH,
      HEIGHT,
    )
  }, [data])

  if (error) return <p style={{ color: 'var(--danger)' }}>{error}</p>
  if (!data) return <p className="dim">Loading graph…</p>

  function handleNodeClick(node: GraphNode) {
    setSelected(node)
    if (node.kind === 'skill') {
      const id = Number(node.id.replace('skill-', ''))
      onOpenSkill(id)
    }
  }

  return (
    <div>
      <h2 className="pixel-font" style={{ fontSize: 18, marginBottom: 8 }}>
        Knowledge Graph
      </h2>
      <p className="dim" style={{ fontSize: 13, marginBottom: 16 }}>
        Every skill node and every Archive principle, wired together by what's actually real:
        parent nodes, the node a principle came from, and nodes the same principle's wording
        relates to.
      </p>

      <div style={{ display: 'flex', gap: 8, marginBottom: 16, flexWrap: 'wrap' }}>
        <span className="dim" style={{ fontSize: 11 }}>
          <span style={{ color: 'var(--text)' }}>▬</span> parent
        </span>
        <span className="dim" style={{ fontSize: 11 }}>
          <span style={{ color: '#facc15' }}>▬</span> principle origin
        </span>
        <span className="dim" style={{ fontSize: 11 }}>
          <span style={{ color: 'var(--border-strong)' }}>▬</span> related
        </span>
        <span className="dim" style={{ fontSize: 11 }}>
          □ skill &nbsp; ○ principle
        </span>
      </div>

      {data.nodes.length === 0 ? (
        <p className="dim">No nodes yet — generate a skill tree first.</p>
      ) : (
        <div className="panel pixel-grid" style={{ overflow: 'auto' }}>
          <svg width={WIDTH} height={HEIGHT} style={{ display: 'block' }}>
            {data.edges.map((e, i) => {
              const a = positions.get(e.source)
              const b = positions.get(e.target)
              if (!a || !b) return null
              const style = EDGE_STYLE[e.kind]
              return (
                <line
                  key={i}
                  x1={a.x}
                  y1={a.y}
                  x2={b.x}
                  y2={b.y}
                  stroke={style.stroke}
                  strokeWidth={style.width}
                  strokeDasharray={style.dash}
                />
              )
            })}

            {data.nodes.map((n) => {
              const pos = positions.get(n.id)
              if (!pos) return null
              const r = nodeRadius(n)
              const isSelected = selected?.id === n.id
              const fill =
                n.kind === 'skill' && n.status === 'mastered'
                  ? '#facc15'
                  : n.kind === 'skill'
                    ? 'var(--panel)'
                    : 'var(--panel)'
              return (
                <g
                  key={n.id}
                  role="button"
                  tabIndex={0}
                  onClick={() => handleNodeClick(n)}
                  onKeyDown={(e) => e.key === 'Enter' && handleNodeClick(n)}
                  style={{ cursor: 'pointer' }}
                >
                  {n.kind === 'skill' ? (
                    <rect
                      x={pos.x - r}
                      y={pos.y - r}
                      width={r * 2}
                      height={r * 2}
                      fill={fill}
                      stroke={isSelected ? 'var(--danger)' : 'var(--text)'}
                      strokeWidth={isSelected ? 2.5 : 1.5}
                    />
                  ) : (
                    <circle
                      cx={pos.x}
                      cy={pos.y}
                      r={r}
                      fill={fill}
                      stroke={isSelected ? 'var(--danger)' : 'var(--text)'}
                      strokeWidth={isSelected ? 2.5 : 1.5}
                    />
                  )}
                  <text
                    x={pos.x}
                    y={pos.y + r + 12}
                    textAnchor="middle"
                    fontSize={9}
                    fill="var(--dim)"
                  >
                    {n.title.length > 14 ? `${n.title.slice(0, 14)}…` : n.title}
                  </text>
                </g>
              )
            })}
          </svg>
        </div>
      )}

      {selected && (
        <div className="panel" style={{ marginTop: 16 }}>
          <p className="dim pixel-font" style={{ fontSize: 9, marginBottom: 6 }}>
            {selected.kind === 'skill' ? 'SKILL NODE' : 'PRINCIPLE'}
          </p>
          <p style={{ fontSize: 14, fontWeight: 600 }}>{selected.title}</p>
          {selected.kind === 'skill' && (
            <p className="dim" style={{ fontSize: 12, marginTop: 4 }}>
              Status: {selected.status} · {selected.node_type}
            </p>
          )}
        </div>
      )}
    </div>
  )
}
