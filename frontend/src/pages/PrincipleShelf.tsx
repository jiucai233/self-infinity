import { useEffect, useState } from 'react'
import { api } from '../api'
import type { Principle } from '../types'

export default function PrincipleShelf() {
  const [principles, setPrinciples] = useState<Principle[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api
      .listPrinciples()
      .then(setPrinciples)
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false))
  }, [])

  if (loading) return <p className="dim">Loading archive…</p>
  if (error) return <p style={{ color: 'var(--danger)' }}>{error}</p>

  return (
    <div>
      <h2 className="pixel-font" style={{ fontSize: 18 }}>
        Archive
      </h2>
      <p className="dim" style={{ marginBottom: 24 }}>
        Each entry is an actionable rule earned from a failed audit.
      </p>

      {principles.length === 0 ? (
        <p className="dim">No entries yet — go fail an audit on the Skills tree first.</p>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {principles.map((p) => (
            <div key={p.id} className="panel">
              <h3 className="pixel-font" style={{ fontSize: 12, color: '#facc15' }}>
                {p.title}
              </h3>
              <p style={{ fontSize: 13, marginTop: 4 }}>{p.body}</p>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
