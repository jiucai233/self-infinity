// Decorative placeholder page — the template's "Map" nav slot has no
// backing feature (this app has one skill tree, not a world map).
export default function Map() {
  return (
    <div>
      <h2 className="pixel-font" style={{ fontSize: 18, marginBottom: 16 }}>
        Map
      </h2>
      <div className="panel">
        <p style={{ marginBottom: 6, fontWeight: 600 }}>Coming soon</p>
        <p className="dim" style={{ fontSize: 13 }}>
          A bird's-eye view across all your skill trees isn't built yet — use the Skills tab for
          now.
        </p>
      </div>
    </div>
  )
}
