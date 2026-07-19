import { useEffect, useState } from 'react'
import SkillTree from './pages/SkillTree'
import SkillNodeDetail from './pages/SkillNodeDetail'
import AuditRoom from './pages/AuditRoom'
import PrincipleShelf from './pages/PrincipleShelf'
import AvatarPage from './pages/AvatarPage'
import Quests from './pages/Quests'
import Guild from './pages/Guild'
import KnowledgeGraph from './pages/KnowledgeGraph'
import Support from './pages/Support'
import Avatar from './components/Avatar'
import ThemeToggle from './components/ThemeToggle'
import { api } from './api'
import type { AuditMode, NodeType } from './types'

type View =
  | { name: 'tree' }
  | { name: 'nodeDetail'; skillId: number }
  | { name: 'audit'; skillId: number; nodeType: NodeType; mode: AuditMode }
type Panel = 'none' | 'principles' | 'avatar' | 'quests' | 'guild' | 'map' | 'support'

function App() {
  const [view, setView] = useState<View>({ name: 'tree' })
  const [panel, setPanel] = useState<Panel>('none')

  // Real mastered-node count, fetched here purely to derive the decorative
  // sidebar "Level" readout below — reuses the same cheap /skills endpoint
  // every other page already calls, no new backend surface. Re-fetched
  // whenever we land back on the tree view since an audit pass may have
  // changed the mastered count.
  const [masteredCount, setMasteredCount] = useState(0)
  useEffect(() => {
    api
      .listSkills()
      .then((skills) => setMasteredCount(skills.filter((s) => s.status === 'mastered').length))
      .catch(() => {})
  }, [view.name])

  const onTree = panel === 'none' && (view.name === 'tree' || view.name === 'nodeDetail')
  const onAvatar = panel === 'avatar'
  const onPrinciples = panel === 'principles'
  const onQuests = panel === 'quests'
  const onGuild = panel === 'guild'
  const onMap = panel === 'map'
  const onSupport = panel === 'support'

  function goToSkills() {
    setPanel('none')
    setView({ name: 'tree' })
  }

  // decorative: Level is derived from the real mastered-node count (no
  // fabricated XP curve), Class is a static flavor string — neither backs a
  // real numeric buff system.
  const level = 1 + Math.floor(masteredCount / 3)
  const flavorClass = 'Auditor Class'

  return (
    <div className="app-shell">
      <aside className="app-sidebar">
        <div>
          <h1 className="pixel-font" style={{ fontSize: 13, margin: 0 }}>
            SELF·INFINITY
          </h1>
          <span className="dim" style={{ fontSize: 11 }}>
            Feynman Audit Loop · V1
          </span>
        </div>

        <div className="app-sidebar-avatar-slot">
          <Avatar compact />
        </div>

        {/* decorative: Level/Class flavor card, per the template's
            "Level 42 / Vanguard Class" sidebar readout. Level is derived
            from real mastered-node count; Class is a static flavor label. */}
        <div className="panel" style={{ padding: '10px 12px' }}>
          <p className="pixel-font" style={{ fontSize: 11, marginBottom: 4 }}>
            Level {level}
          </p>
          <p className="dim" style={{ fontSize: 11 }}>
            {flavorClass}
          </p>
        </div>

        <nav className="app-sidebar-nav">
          <button
            className={`app-sidebar-nav-item${onAvatar ? ' app-sidebar-nav-item--active' : ''}`}
            onClick={() => setPanel((p) => (p === 'avatar' ? 'none' : 'avatar'))}
          >
            Character
          </button>
          <button
            className={`app-sidebar-nav-item${onTree ? ' app-sidebar-nav-item--active' : ''}`}
            onClick={goToSkills}
          >
            Skills
          </button>
          <button
            className={`app-sidebar-nav-item${onPrinciples ? ' app-sidebar-nav-item--active' : ''}`}
            onClick={() => setPanel((p) => (p === 'principles' ? 'none' : 'principles'))}
          >
            Archive
          </button>
          <button
            className={`app-sidebar-nav-item${onQuests ? ' app-sidebar-nav-item--active' : ''}`}
            onClick={() => setPanel((p) => (p === 'quests' ? 'none' : 'quests'))}
          >
            Quests
          </button>
          <button
            className={`app-sidebar-nav-item${onGuild ? ' app-sidebar-nav-item--active' : ''}`}
            onClick={() => setPanel((p) => (p === 'guild' ? 'none' : 'guild'))}
          >
            Guild
          </button>
          <button
            className={`app-sidebar-nav-item${onMap ? ' app-sidebar-nav-item--active' : ''}`}
            onClick={() => setPanel((p) => (p === 'map' ? 'none' : 'map'))}
          >
            Graph
          </button>
          <button
            className={`app-sidebar-nav-item${onSupport ? ' app-sidebar-nav-item--active' : ''}`}
            onClick={() => setPanel((p) => (p === 'support' ? 'none' : 'support'))}
          >
            Support
          </button>
          {/* decorative: no real auth system exists — a dim, disabled row
              instead of building a fake login/logout flow. */}
          <button className="app-sidebar-nav-item dim" disabled style={{ cursor: 'default' }}>
            Log Out
          </button>
        </nav>

        <div style={{ flex: 1 }} />

        <button className="accent" onClick={goToSkills}>
          New Mission
        </button>
      </aside>

      <ThemeToggle />

      <main className="app-main">
        {panel === 'principles' ? (
          <PrincipleShelf />
        ) : panel === 'avatar' ? (
          <AvatarPage onInitiateMission={goToSkills} />
        ) : panel === 'quests' ? (
          <Quests />
        ) : panel === 'guild' ? (
          <Guild />
        ) : panel === 'map' ? (
          <KnowledgeGraph
            onOpenSkill={(skillId) => {
              setPanel('none')
              setView({ name: 'nodeDetail', skillId })
            }}
          />
        ) : panel === 'support' ? (
          <Support />
        ) : view.name === 'tree' ? (
          <SkillTree
            onAudit={(skillId, nodeType, mode) =>
              setView({ name: 'audit', skillId, nodeType, mode })
            }
            onOpenDetail={(skillId) => setView({ name: 'nodeDetail', skillId })}
          />
        ) : view.name === 'nodeDetail' ? (
          <SkillNodeDetail
            skillId={view.skillId}
            onBack={goToSkills}
            onAudit={(skillId, nodeType, mode) =>
              setView({ name: 'audit', skillId, nodeType, mode })
            }
          />
        ) : (
          <AuditRoom
            skillId={view.skillId}
            nodeType={view.nodeType}
            mode={view.mode}
            onDone={goToSkills}
          />
        )}
      </main>
    </div>
  )
}

export default App
