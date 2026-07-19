import { useEffect, useRef, useState } from 'react'
import ForceGraph, { type NodeObject } from 'force-graph'
import { api } from '../api'
import type { GraphEdge, GraphNode, GraphResponse } from '../types'

// Repurposes the template's "Map" nav slot — a knowledge graph is, in a
// real sense, a map of everything you've learned. Renders the real skill
// tree (parent edges) plus the Archive's principles wired to the real node
// each one came from ("origin" edges, via Principle.source_session_id ->
// AuditSession.skill_id on the backend) and to any other node the same
// keyword-overlap heuristic app/agents/retrieval.py already uses for
// in-audit retrieval finds related ("related" edges) — no fabricated
// connections.
//
// 2026-07-20: rendered with the `force-graph` library (2D canvas, d3-force
// physics) instead of the hand-rolled SVG + custom force simulation from
// the previous version — chosen over a full 3D (three.js/3d-force-graph)
// approach specifically because dense text labels stay readable without 3D
// perspective distortion, matching how Obsidian's own graph view is 2D by
// default. Drag-to-reposition and wheel/pinch-to-zoom are the library's
// built-in behavior, not custom pointer-event code.
const WIDTH = 900
const HEIGHT = 620

type FGNode = GraphNode & NodeObject
type FGLink = { source: string; target: string; kind: GraphEdge['kind'] }

function cssVar(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim() || '#888'
}

// Read fresh on every call (not cached) so colors track the live/light-dark
// theme toggle without needing to re-instantiate the graph on theme change.
function nodeColor(node: FGNode): string {
  if (node.kind === 'skill' && node.status === 'mastered') return '#facc15'
  return node.kind === 'skill' ? cssVar('--text') : cssVar('--dim')
}

function linkColor(link: FGLink): string {
  if (link.kind === 'origin') return '#facc15'
  if (link.kind === 'parent') return cssVar('--text')
  return cssVar('--border-strong')
}

export default function KnowledgeGraph({
  onOpenSkill,
}: {
  onOpenSkill: (skillId: number) => void
}) {
  const containerRef = useRef<HTMLDivElement | null>(null)
  const graphRef = useRef<InstanceType<typeof ForceGraph> | null>(null)
  const [data, setData] = useState<GraphResponse | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<GraphNode | null>(null)

  useEffect(() => {
    api
      .getGraph()
      .then(setData)
      .catch((e) => setError(String(e)))
  }, [])

  useEffect(() => {
    if (!data || !containerRef.current) return

    const graph = new ForceGraph(containerRef.current)
    graphRef.current = graph

    graph
      .width(WIDTH)
      .height(HEIGHT)
      .backgroundColor('rgba(0,0,0,0)')
      .graphData({
        nodes: data.nodes as FGNode[],
        links: data.edges.map((e) => ({ ...e })) as unknown as FGLink[],
      })
      .nodeId('id')
      .nodeVal((n) => ((n as FGNode).kind === 'principle' ? 3 : 5))
      .nodeColor((n) => nodeColor(n as FGNode))
      .nodeLabel((n) => (n as FGNode).title)
      .nodeCanvasObjectMode(() => 'after')
      .nodeCanvasObject((n, ctx, scale) => {
        const node = n as FGNode
        const label = node.title.length > 16 ? `${node.title.slice(0, 16)}…` : node.title
        const fontSize = 10 / scale
        ctx.font = `${fontSize}px sans-serif`
        ctx.textAlign = 'center'
        ctx.textBaseline = 'top'
        ctx.fillStyle = cssVar('--dim')
        ctx.fillText(label, node.x ?? 0, (node.y ?? 0) + 8)
      })
      .linkColor((l) => linkColor(l as unknown as FGLink))
      .linkWidth((l) => ((l as unknown as FGLink).kind === 'parent' ? 2 : 1))
      .linkLineDash((l) =>
        (l as unknown as FGLink).kind === 'parent' ? null : [2, 2],
      )
      .minZoom(0.3)
      .maxZoom(3)
      .onNodeClick((n) => {
        const node = n as FGNode
        setSelected(node)
        if (node.kind === 'skill') {
          onOpenSkill(Number(node.id.replace('skill-', '')))
        }
      })

    return () => {
      graph._destructor()
      graphRef.current = null
    }
  }, [data, onOpenSkill])

  if (error) return <p style={{ color: 'var(--danger)' }}>{error}</p>
  if (!data) return <p className="dim">Loading graph…</p>

  return (
    <div>
      <h2 className="pixel-font" style={{ fontSize: 18, marginBottom: 8 }}>
        Knowledge Graph
      </h2>
      <p className="dim" style={{ fontSize: 13, marginBottom: 16 }}>
        Every skill node and every Archive principle, wired together by what's actually real:
        parent nodes, the node a principle came from, and nodes the same principle's wording
        relates to. Drag a node to reposition it, scroll or pinch to zoom.
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
          ● skill (larger, gold when mastered) &nbsp; ● principle (smaller, dim)
        </span>
      </div>

      {data.nodes.length === 0 ? (
        <p className="dim">No nodes yet — generate a skill tree first.</p>
      ) : (
        <div className="panel" style={{ overflow: 'auto', padding: 0 }}>
          <div ref={containerRef} style={{ width: WIDTH, height: HEIGHT }} />
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
