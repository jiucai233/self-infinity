// Decorative placeholder page — the template's "Quests" nav slot has no
// backing feature in this app (no quest/mission system exists beyond the
// Skills tree itself). Static flavor content only, themed to the app's
// real learning-audit loop rather than the template's sci-fi flavor.
export default function Quests() {
  return (
    <div>
      <h2 className="pixel-font" style={{ fontSize: 18, marginBottom: 16 }}>
        Quests
      </h2>
      <p className="dim" style={{ marginBottom: 24 }}>
        A running list of learning challenges — coming soon.
      </p>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        <div className="panel">
          <h3 className="pixel-font" style={{ fontSize: 12, marginBottom: 6 }}>
            Weekly Streak
          </h3>
          <p className="dim" style={{ fontSize: 13 }}>
            Pass three audits in a row without a failed attempt.
          </p>
        </div>
        <div className="panel">
          <h3 className="pixel-font" style={{ fontSize: 12, marginBottom: 6 }}>
            Deep Dive
          </h3>
          <p className="dim" style={{ fontSize: 13 }}>
            Clear a full concept subtree in Night mode.
          </p>
        </div>
      </div>
    </div>
  )
}
