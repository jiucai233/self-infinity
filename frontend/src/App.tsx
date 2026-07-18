import { useState } from 'react'
import SkillTree from './pages/SkillTree'
import AuditRoom from './pages/AuditRoom'
import PrincipleShelf from './pages/PrincipleShelf'
import type { NodeType } from './types'

type View = { name: 'tree' } | { name: 'audit'; skillId: number; nodeType: NodeType }

function App() {
  const [view, setView] = useState<View>({ name: 'tree' })
  const [showPrinciples, setShowPrinciples] = useState(false)

  return (
    <div>
      <nav
        style={{
          display: 'flex',
          gap: 12,
          padding: '16px 24px',
          borderBottom: '2px solid var(--border)',
          alignItems: 'baseline',
        }}
      >
        <h1 style={{ fontSize: 18, margin: 0 }}>SELF·INFINITY</h1>
        <span className="dim" style={{ fontSize: 12 }}>
          费曼审计闭环 · V1
        </span>
        <div style={{ flex: 1 }} />
        <button
          onClick={() => {
            setShowPrinciples(false)
            setView({ name: 'tree' })
          }}
        >
          技能树
        </button>
        <button onClick={() => setShowPrinciples((v) => !v)}>
          {showPrinciples ? '关闭原则卷轴' : '原则卷轴'}
        </button>
      </nav>

      <main style={{ padding: 24, maxWidth: 880, margin: '0 auto' }}>
        {showPrinciples ? (
          <PrincipleShelf />
        ) : view.name === 'tree' ? (
          <SkillTree
            onAudit={(skillId, nodeType) => setView({ name: 'audit', skillId, nodeType })}
          />
        ) : (
          <AuditRoom
            skillId={view.skillId}
            nodeType={view.nodeType}
            onDone={() => setView({ name: 'tree' })}
          />
        )}
      </main>
    </div>
  )
}

export default App
