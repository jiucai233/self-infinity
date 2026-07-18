import { useState } from 'react'
import SkillTree from './pages/SkillTree'
import AuditRoom from './pages/AuditRoom'
import PrincipleShelf from './pages/PrincipleShelf'
import AvatarPage from './pages/AvatarPage'
import Avatar from './components/Avatar'
import type { NodeType } from './types'

type View = { name: 'tree' } | { name: 'audit'; skillId: number; nodeType: NodeType }
type Panel = 'none' | 'principles' | 'avatar'

function App() {
  const [view, setView] = useState<View>({ name: 'tree' })
  const [panel, setPanel] = useState<Panel>('none')

  return (
    <div>
      <nav
        style={{
          display: 'flex',
          gap: 12,
          padding: '16px 24px',
          borderBottom: '2px solid var(--border)',
          alignItems: 'center',
        }}
      >
        <h1 style={{ fontSize: 18, margin: 0 }}>SELF·INFINITY</h1>
        <span className="dim" style={{ fontSize: 12 }}>
          费曼审计闭环 · V1
        </span>
        <div style={{ flex: 1 }} />
        <Avatar compact />
        <button
          onClick={() => {
            setPanel('none')
            setView({ name: 'tree' })
          }}
        >
          技能树
        </button>
        <button onClick={() => setPanel((p) => (p === 'avatar' ? 'none' : 'avatar'))}>
          {panel === 'avatar' ? '关闭分身' : '分身'}
        </button>
        <button onClick={() => setPanel((p) => (p === 'principles' ? 'none' : 'principles'))}>
          {panel === 'principles' ? '关闭原则卷轴' : '原则卷轴'}
        </button>
      </nav>

      <main style={{ padding: 24, maxWidth: 880, margin: '0 auto' }}>
        {panel === 'principles' ? (
          <PrincipleShelf />
        ) : panel === 'avatar' ? (
          <AvatarPage />
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
