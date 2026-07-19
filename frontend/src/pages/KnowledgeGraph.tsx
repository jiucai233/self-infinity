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
const DEFAULT_WIDTH = 900
const DEFAULT_HEIGHT = 620

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

// Real edge count per node — used to size hub nodes larger (more
// connections = more central to what's been learned) and to decide which
// nodes get an inline label, the same "cluster hubs are labeled, leaves
// aren't" visual hierarchy a real Obsidian graph settles into once it has
// enough notes to get dense.
function computeDegrees(edges: GraphResponse['edges']): Map<string, number> {
  const degrees = new Map<string, number>()
  for (const e of edges) {
    degrees.set(e.source, (degrees.get(e.source) ?? 0) + 1)
    degrees.set(e.target, (degrees.get(e.target) ?? 0) + 1)
  }
  return degrees
}

// Small graphs have no clutter problem, so every node keeps its label —
// the hub-only threshold only kicks in once there's enough nodes for
// labels to start overlapping.
const LABEL_ALL_THRESHOLD = 15
const HUB_DEGREE_THRESHOLD = 3

export default function KnowledgeGraph({
  onOpenSkill,
  width = DEFAULT_WIDTH,
  height = DEFAULT_HEIGHT,
  compact = false,
}: {
  onOpenSkill: (skillId: number) => void
  width?: number
  height?: number
  // Trims the heading/description/legend so the component fits in a narrow
  // side-by-side column (used on the Skills page) instead of a full-width
  // standalone section.
  compact?: boolean
}) {
  const containerRef = useRef<HTMLDivElement | null>(null)
  const graphRef = useRef<InstanceType<typeof ForceGraph> | null>(null)
  const [data, setData] = useState<GraphResponse | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<GraphNode | null>(null)
  // Mirrors `selected` for the nodeCanvasObject closure below, which is set
  // up once per graph instance (not re-run on every selection change — that
  // would tear down and re-warm the whole force simulation just to update a
  // label) but still needs to know the current selection so a clicked leaf
  // node's label stays visible even below the hub-degree threshold.
  const selectedRef = useRef<GraphNode | null>(null)

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

    const degrees = computeDegrees(data.edges)
    const labelAll = data.nodes.length <= LABEL_ALL_THRESHOLD
    const nodeDegree = (node: FGNode) => degrees.get(node.id) ?? 0
    const nodeRadius = (node: FGNode) => {
      const base = node.kind === 'principle' ? 2 : 4
      return Math.min(base + nodeDegree(node) * 1.1, 20)
    }

    graph
      .width(width)
      .height(height)
      .backgroundColor('rgba(0,0,0,0)')
      .graphData({
        nodes: data.nodes as FGNode[],
        links: data.edges.map((e) => ({ ...e })) as unknown as FGLink[],
      })
      .nodeId('id')
      .nodeVal((n) => nodeRadius(n as FGNode))
      .nodeColor((n) => nodeColor(n as FGNode))
      .nodeLabel((n) => (n as FGNode).title)
      .nodeCanvasObjectMode(() => 'after')
      .nodeCanvasObject((n, ctx, scale) => {
        const node = n as FGNode
        if (!labelAll && nodeDegree(node) < HUB_DEGREE_THRESHOLD && selectedRef.current?.id !== node.id) {
          return
        }
        const label = node.title.length > 16 ? `${node.title.slice(0, 16)}…` : node.title
        const fontSize = 10 / scale
        ctx.font = `${fontSize}px sans-serif`
        ctx.textAlign = 'center'
        ctx.textBaseline = 'top'
        ctx.fillStyle = cssVar('--dim')
        ctx.fillText(label, node.x ?? 0, (node.y ?? 0) + nodeRadius(node) + 2)
      })
      .linkColor((l) => linkColor(l as unknown as FGLink))
      .linkWidth((l) => ((l as unknown as FGLink).kind === 'parent' ? 2 : 1))
      .linkLineDash((l) =>
        (l as unknown as FGLink).kind === 'parent' ? null : [2, 2],
      )
      .minZoom(0.3)
      .maxZoom(8)
      // Precompute most of the layout synchronously before the first paint
      // instead of animating from a random start, and cap the post-warmup
      // animated loop at a fixed tick count instead of the library's default
      // wall-clock cooldown (~15s) — on a ~35-node graph that default left
      // nodes sitting overlapped in a fixed-zoom crop of the center for 15
      // real seconds before the eventual re-fit. With warmup already having
      // done the heavy lifting, cooldownTicks only needs to be enough for a
      // last bit of settling before onEngineStop fires and re-fits below.
      .warmupTicks(100)
      .cooldownTicks(50)
      .onNodeClick((n) => {
        const node = n as FGNode
        selectedRef.current = node
        setSelected(node)
        if (node.kind === 'skill') {
          onOpenSkill(Number(node.id.replace('skill-', '')))
        }
      })
      .onEngineStop(() => graphRef.current?.zoomToFit(200, 24))

    return () => {
      graph._destructor()
      graphRef.current = null
    }
  }, [data, onOpenSkill, width, height])

  if (error) return <p style={{ color: 'var(--danger)' }}>{error}</p>
  if (!data) return <p className="dim">Loading graph…</p>

  return (
    <div>
      <h2 className="pixel-font" style={{ fontSize: compact ? 14 : 18, marginBottom: 8 }}>
        Knowledge Graph
      </h2>
      {!compact && (
        <p className="dim" style={{ fontSize: 13, marginBottom: 16 }}>
          Every skill node and every Archive principle, wired together by what's actually real:
          parent nodes, the node a principle came from, and nodes the same principle's wording
          relates to. Drag a node to reposition it, scroll or pinch to zoom.
        </p>
      )}

      <div
        style={{
          display: 'flex',
          gap: compact ? 6 : 8,
          marginBottom: compact ? 8 : 16,
          flexWrap: 'wrap',
        }}
      >
        <span className="dim" style={{ fontSize: 11 }}>
          <span style={{ color: 'var(--text)' }}>▬</span> parent
        </span>
        <span className="dim" style={{ fontSize: 11 }}>
          <span style={{ color: '#facc15' }}>▬</span> origin
        </span>
        <span className="dim" style={{ fontSize: 11 }}>
          <span style={{ color: 'var(--border-strong)' }}>▬</span> related
        </span>
        {!compact && (
          <span className="dim" style={{ fontSize: 11 }}>
            ● skill (larger, gold when mastered) &nbsp; ● principle (smaller, dim)
          </span>
        )}
      </div>

      {data.nodes.length === 0 ? (
        <p className="dim">No nodes yet — generate a skill tree first.</p>
      ) : (
        <div className="panel" style={{ overflow: 'auto', padding: 0 }}>
          <div ref={containerRef} style={{ width, height }} />
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
