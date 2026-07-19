import { useState } from 'react'
import SkillTree from './pages/SkillTree'
import AuditRoom from './pages/AuditRoom'
import PrincipleShelf from './pages/PrincipleShelf'
import AvatarPage from './pages/AvatarPage'
import Avatar from './components/Avatar'
import ThemeToggle from './components/ThemeToggle'
import type { AuditMode, NodeType } from './types'

type View =
  | { name: 'tree' }
  | { name: 'audit'; skillId: number; nodeType: NodeType; mode: AuditMode }
type Panel = 'none' | 'principles' | 'avatar'

function App() {
  const [view, setView] = useState<View>({ name: 'tree' })
  const [panel, setPanel] = useState<Panel>('none')

  const onTree = panel === 'none' && view.name === 'tree'
  const onAvatar = panel === 'avatar'
  const onPrinciples = panel === 'principles'
  // The audit room renders its own immersive dark canvas (see AuditRoom.tsx's
  // .audit-immersive) — drop <main>'s default padding only while it's shown
  // so the dark background can bleed edge-to-edge instead of leaving a
  // padded frame of the normal theme visible around it.
  const isAuditView = panel === 'none' && view.name === 'audit'

  return (
    <div className="app-shell">
      <aside className="app-sidebar">
        <div>
          <h1 className="pixel-font" style={{ fontSize: 13, margin: 0 }}>
            SELF·INFINITY
          </h1>
          <span className="dim" style={{ fontSize: 11 }}>
            费曼审计闭环 · V1
          </span>
        </div>

        <div className="app-sidebar-avatar-slot">
          <Avatar compact />
        </div>

        <nav className="app-sidebar-nav">
          <button
            className={`app-sidebar-nav-item${onTree ? ' app-sidebar-nav-item--active' : ''}`}
            onClick={() => {
              setPanel('none')
              setView({ name: 'tree' })
            }}
          >
            技能树
          </button>
          <button
            className={`app-sidebar-nav-item${onAvatar ? ' app-sidebar-nav-item--active' : ''}`}
            onClick={() => setPanel((p) => (p === 'avatar' ? 'none' : 'avatar'))}
          >
            分身
          </button>
          <button
            className={`app-sidebar-nav-item${onPrinciples ? ' app-sidebar-nav-item--active' : ''}`}
            onClick={() => setPanel((p) => (p === 'principles' ? 'none' : 'principles'))}
          >
            原则卷轴
          </button>
        </nav>

        <div style={{ flex: 1 }} />
      </aside>

      <ThemeToggle />

      <main className={`app-main${isAuditView ? ' app-main--bleed' : ''}`}>
        {panel === 'principles' ? (
          <PrincipleShelf />
        ) : panel === 'avatar' ? (
          <AvatarPage />
        ) : view.name === 'tree' ? (
          <SkillTree
            onAudit={(skillId, nodeType, mode) =>
              setView({ name: 'audit', skillId, nodeType, mode })
            }
          />
        ) : (
          <AuditRoom
            skillId={view.skillId}
            nodeType={view.nodeType}
            mode={view.mode}
            onDone={() => setView({ name: 'tree' })}
          />
        )}
      </main>
    </div>
  )
}

export default App
