// Decorative placeholder page — the template's "Guild" nav slot has no
// backing feature (this app has no social/multiplayer system).
export default function Guild() {
  return (
    <div>
      <h2 className="pixel-font" style={{ fontSize: 18, marginBottom: 16 }}>
        Guild
      </h2>
      <div className="panel">
        <p style={{ marginBottom: 6, fontWeight: 600 }}>Coming soon</p>
        <p className="dim" style={{ fontSize: 13 }}>
          Study groups and shared skill trees aren't built yet — for now it's just you and the
          Auditor.
        </p>
      </div>
    </div>
  )
}
