import { useEffect, useRef, useState } from 'react'
import { api } from '../api'
import type { AuditMode, AuditTurn, NodeType, TurnResultResponse } from '../types'

type Phase = 'loading' | 'active' | 'passed' | 'failed' | 'reflected'

// Decision note (M3 "spoken explanations"): the whitepaper's end-state
// (§4.2) is sending raw audio to a multimodal model, but the backend has no
// audio pipeline and the offline MockProvider can't consume audio at all.
// Instead we use the browser-native Web Speech API to transcribe speech to
// text client-side and feed the result into the existing text `input` state
// / submitTurn flow unchanged. This ships the actual user-facing feature
// ("speak instead of type") without backend changes, and works the same
// regardless of which LLM provider is configured.
function getSpeechRecognitionCtor(): (new () => SpeechRecognitionLike) | null {
  if (typeof window === 'undefined') return null
  return window.SpeechRecognition ?? window.webkitSpeechRecognition ?? null
}

// A pixel-bust NPC portrait for the Auditor, distinct from the player's
// PixelFigure (components/Avatar.tsx) — a wider "head" with a single visor
// bar instead of a face, no legs (bust only), reads as a separate character
// rather than a re-skinned player avatar. Per the visual-novel dialogue-box
// convention (portrait + name label next to the text box) rather than this
// app's previous faceless log.
function AuditorPortrait({ size = 40 }: { size?: number }) {
  const height = (size / 12) * 12
  return (
    <svg
      width={size}
      height={height}
      viewBox="0 0 12 12"
      shapeRendering="crispEdges"
      role="img"
      aria-label="Auditor"
      style={{ flexShrink: 0 }}
    >
      <rect x="1" y="1" width="10" height="9" fill="var(--text)" />
      <rect x="2" y="4" width="8" height="2" fill="var(--bg)" />
      <rect x="4" y="10" width="1" height="2" fill="var(--text)" />
      <rect x="7" y="10" width="1" height="2" fill="var(--text)" />
    </svg>
  )
}

function PlayerBadge({ size = 40 }: { size?: number }) {
  return (
    <div
      className="pixel-border"
      style={{
        width: size,
        height: size,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        flexShrink: 0,
      }}
    >
      <span className="pixel-font" style={{ fontSize: 10 }}>
        YOU
      </span>
    </div>
  )
}

function ChatMessage({ role, content, roleLabel }: AuditTurn & { roleLabel: string }) {
  const isAuditor = role === 'auditor'
  return (
    <div style={{ display: 'flex', gap: 12, padding: '12px 0' }}>
      {isAuditor ? <AuditorPortrait /> : <PlayerBadge />}
      <div style={{ flex: 1, minWidth: 0 }}>
        <p className="pixel-font" style={{ fontSize: 10, marginBottom: 4 }}>
          {isAuditor ? roleLabel : 'You'}
        </p>
        <p style={{ fontSize: 14, lineHeight: 1.6 }}>{content}</p>
      </div>
    </div>
  )
}

export default function AuditRoom({
  skillId,
  nodeType,
  mode = 'day',
  onDone,
}: {
  skillId: number
  nodeType: NodeType
  mode?: AuditMode
  onDone: () => void
}) {
  const isTask = nodeType === 'task'
  const roleLabel = isTask ? 'Task Verifier' : 'Feynman Auditor'
  const [phase, setPhase] = useState<Phase>('loading')
  const [auditId, setAuditId] = useState<number | null>(null)
  const [turns, setTurns] = useState<AuditTurn[]>([])
  const [input, setInput] = useState('')
  const [verdict, setVerdict] = useState<TurnResultResponse | null>(null)
  const [reflection, setReflection] = useState('')
  const [principleTitle, setPrincipleTitle] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [listening, setListening] = useState(false)
  const recognitionRef = useRef<SpeechRecognitionLike | null>(null)
  const speechSupported = getSpeechRecognitionCtor() !== null

  useEffect(() => {
    return () => {
      recognitionRef.current?.stop()
    }
  }, [])

  function toggleListening() {
    if (listening) {
      recognitionRef.current?.stop()
      return
    }
    const Ctor = getSpeechRecognitionCtor()
    if (!Ctor) return
    const recognition = new Ctor()
    recognition.lang = 'zh-CN'
    recognition.continuous = true
    recognition.interimResults = false
    recognition.onresult = (event) => {
      let transcript = ''
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const result = event.results[i]
        if (result.isFinal) transcript += result[0].transcript
      }
      if (transcript) {
        setInput((prev) => (prev ? `${prev}${transcript}` : transcript))
      }
    }
    recognition.onerror = (event) => {
      setError(
        event.error === 'not-allowed' || event.error === 'permission-denied'
          ? 'Microphone permission denied — voice input unavailable'
          : `Speech recognition error: ${event.error}`,
      )
      setListening(false)
    }
    recognition.onend = () => {
      setListening(false)
    }
    recognitionRef.current = recognition
    setError(null)
    setListening(true)
    recognition.start()
  }

  useEffect(() => {
    api
      .startAudit(skillId, mode)
      .then((res) => {
        setAuditId(res.session.id)
        setTurns(res.session.turns)
        setPhase('active')
      })
      .catch((e) => setError(String(e)))
  }, [skillId, mode])

  async function submitTurn() {
    if (!auditId || !input.trim()) return
    setSubmitting(true)
    setError(null)
    const content = input.trim()
    setTurns((t) => [...t, { role: 'user', content }])
    setInput('')
    try {
      const result = await api.submitTurn(auditId, content)
      if (result.type === 'probe' && result.question) {
        setTurns((t) => [...t, { role: 'auditor', content: result.question! }])
      } else {
        setVerdict(result)
        setPhase(result.passed ? 'passed' : 'failed')
      }
    } catch (e) {
      setError(String(e))
    } finally {
      setSubmitting(false)
    }
  }

  async function submitReflection() {
    if (!auditId || !reflection.trim()) return
    setSubmitting(true)
    setError(null)
    try {
      const principle = await api.submitReflection(auditId, reflection.trim())
      setPrincipleTitle(principle.title)
      setPhase('reflected')
    } catch (e) {
      setError(String(e))
    } finally {
      setSubmitting(false)
    }
  }

  if (phase === 'loading') return <p className="dim">{roleLabel} is entering…</p>

  // Real turn counter — number of user turns submitted so far in this
  // session.
  const userTurnCount = turns.filter((t) => t.role === 'user').length

  return (
    <div>
      <button onClick={onDone} style={{ marginBottom: 16 }}>
        ← Back to Skills
      </button>

      <div className="audit-room-layout">
        <div>
          {/* NPC intro card — a persistent character header (portrait + name
              + what they're grilling you on), visual-novel style, instead of
              a faceless scrolling log. */}
          <div className="panel" style={{ display: 'flex', gap: 16, alignItems: 'center' }}>
            <AuditorPortrait size={56} />
            <div>
              <h2 className="pixel-font" style={{ fontSize: 15, marginBottom: 4 }}>
                {roleLabel}
              </h2>
              <p className="dim" style={{ fontSize: 12 }}>
                {isTask
                  ? "Show me you did it. I'm not interested in theory."
                  : "Explain it like I've never heard of this. I will keep pushing."}
              </p>
            </div>
          </div>

          <div className="panel" style={{ marginTop: 16 }}>
            <div style={{ display: 'flex', flexDirection: 'column' }}>
              {turns.map((t, i) => (
                <ChatMessage key={i} role={t.role} content={t.content} roleLabel={roleLabel} />
              ))}
            </div>

            {phase === 'active' && (
              <div style={{ marginTop: 8, borderTop: '1px solid var(--border)', paddingTop: 16 }}>
                <textarea
                  rows={4}
                  value={input}
                  placeholder={
                    isTask
                      ? 'Explain exactly what you plan to do…'
                      : "Explain it to someone who's never heard of this…"
                  }
                  onChange={(e) => setInput(e.target.value)}
                  disabled={submitting}
                />
                <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
                  <button
                    className="accent"
                    onClick={submitTurn}
                    disabled={submitting || !input.trim()}
                  >
                    {submitting
                      ? `${roleLabel} is thinking…`
                      : isTask
                        ? 'Submit Plan'
                        : 'Submit Explanation'}
                  </button>
                  {speechSupported && (
                    <button
                      type="button"
                      onClick={toggleListening}
                      disabled={submitting}
                      style={
                        listening
                          ? { borderColor: 'var(--danger)', color: 'var(--danger)' }
                          : undefined
                      }
                      title="Voice Input"
                    >
                      {listening ? '● Recording…' : 'Voice Input'}
                    </button>
                  )}
                  {!speechSupported && (
                    <button
                      type="button"
                      disabled
                      title="Voice input not supported in this browser"
                    >
                      Voice Input
                    </button>
                  )}
                </div>
              </div>
            )}

            {(phase === 'passed' || phase === 'failed' || phase === 'reflected') && verdict && (
              <div
                style={{
                  borderTop: '1px solid var(--border)',
                  paddingTop: 12,
                  marginTop: 4,
                }}
              >
                <p
                  className="pixel-font"
                  style={{
                    color: phase === 'failed' ? 'var(--danger)' : '#facc15',
                    fontSize: 12,
                    lineHeight: 1.8,
                  }}
                >
                  {verdict.passed
                    ? isTask
                      ? '✓ Task Complete'
                      : '✓ Audit Passed'
                    : isTask
                      ? '✗ Not There Yet'
                      : '✗ Audit Failed'}{' '}
                  · {verdict.score} pts
                </p>
                {verdict.passed && verdict.reward_amount != null && (
                  <p style={{ fontSize: 13, marginTop: 2, color: 'var(--accent)' }}>
                    +{verdict.reward_amount} reward
                    {verdict.reward_multiplier != null && ` (×${verdict.reward_multiplier})`}
                  </p>
                )}
                <p className="dim" style={{ fontSize: 13, marginTop: 4 }}>
                  {verdict.comment}
                </p>
                {verdict.gaps && verdict.gaps.length > 0 && (
                  <ul style={{ fontSize: 13, marginTop: 8, paddingLeft: 18 }}>
                    {verdict.gaps.map((g, i) => (
                      <li key={i}>{g}</li>
                    ))}
                  </ul>
                )}
                {verdict.passed && verdict.unlocked_skill_ids.length > 0 && (
                  <p style={{ fontSize: 13, marginTop: 8 }}>
                    Unlocked {verdict.unlocked_skill_ids.length} new node
                    {verdict.unlocked_skill_ids.length === 1 ? '' : 's'}
                  </p>
                )}
              </div>
            )}

            {phase === 'failed' && (
              <div style={{ marginTop: 8 }}>
                <p className="dim" style={{ fontSize: 12, marginBottom: 6 }}>
                  Mandatory reflection: why didn't this land? What will you do differently next
                  time?
                </p>
                <textarea
                  rows={3}
                  value={reflection}
                  onChange={(e) => setReflection(e.target.value)}
                  disabled={submitting}
                />
                <button
                  style={{ marginTop: 8 }}
                  onClick={submitReflection}
                  disabled={submitting || !reflection.trim()}
                >
                  {submitting ? 'Distilling…' : 'Submit Reflection, Generate Archive Entry'}
                </button>
              </div>
            )}

            {phase === 'reflected' && principleTitle && (
              <div className="panel" style={{ marginTop: 8 }}>
                <p style={{ fontSize: 12 }} className="dim">
                  New Archive Entry
                </p>
                <p>{principleTitle}</p>
              </div>
            )}

            {phase === 'passed' && (
              <button className="accent" style={{ marginTop: 8 }} onClick={onDone}>
                Back to Skills
              </button>
            )}
          </div>
        </div>

        {/* Real session facts only. No progress-toward-cap bar anymore —
            2026-07-19: the Auditor no longer stops at a fixed turn count
            (see backend/app/agents/auditor.py), it decides when it's
            satisfied or has found a real gap. A "% toward max" bar would
            misrepresent that as a target length, so this now just shows
            the honest running count. */}
        <div className="panel">
          <p className="dim pixel-font" style={{ fontSize: 9, marginBottom: 8 }}>
            ACTIVE_AUDIT
          </p>
          <p className="pixel-font" style={{ fontSize: 12, marginBottom: 8 }}>
            {roleLabel}
          </p>
          <p className="dim" style={{ fontSize: 12, marginBottom: 12 }}>
            Node type: {isTask ? 'Task · Just get it done' : 'Concept · Explain the why'}
          </p>
          <p className="dim" style={{ fontSize: 11, marginBottom: 4 }}>
            Turns Submitted
          </p>
          <p className="pixel-font" style={{ fontSize: 16 }}>
            {userTurnCount}
          </p>
          <p className="dim" style={{ fontSize: 11, marginTop: 8 }}>
            No fixed round count — the Auditor keeps going until it's either satisfied or has
            found a real gap.
          </p>
        </div>
      </div>

      {error && <p style={{ color: 'var(--danger)', marginTop: 12 }}>{error}</p>}
    </div>
  )
}
