// Decorative placeholder page — the template's "Support" nav slot has no
// backing feature (no ticketing/help-desk system exists).
export default function Support() {
  return (
    <div>
      <h2 className="pixel-font" style={{ fontSize: 18, marginBottom: 16 }}>
        Support
      </h2>
      <div className="panel">
        <p style={{ marginBottom: 6, fontWeight: 600 }}>Coming soon</p>
        <p className="dim" style={{ fontSize: 13 }}>
          No help desk yet — if something's broken, that's on us, not you.
        </p>
      </div>
    </div>
  )
}
